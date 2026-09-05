// SPDX-License-Identifier: Apache-2.0
import CoreServices
import Foundation
import OSLog

/// A compact, Sendable summary of one FSEvents callback. Cuelixa performs a
/// bounded full reconciliation for every delivered hierarchy change, while
/// retaining the flags that require special recovery semantics.
struct LibraryChangeEvent: Sendable {
  let rootChanged: Bool
  let mustRescan: Bool
}

/// Watches the whole lesson-library hierarchy with the native FSEvents service.
/// A coalescing latency is intentional: Cuelixa needs to know that the tree
/// changed, not receive one wakeup per filesystem operation.
@MainActor
final class LibraryChangeMonitor {
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "Library")
  private let root: URL
  private let onChange: @MainActor (LibraryChangeEvent) -> Void
  private let eventQueue = DispatchQueue(
    label: "io.github.erhansavas.Cuelixa.library-events", qos: .utility)
  private var stream: FSEventStreamRef?

  init(
    root: URL = AppPaths.current.library,
    onChange: @escaping @MainActor (LibraryChangeEvent) -> Void
  ) {
    self.root = root
    self.onChange = onChange
  }

  @discardableResult
  func start() -> Bool {
    guard stream == nil else { return true }

    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil)

    let callback: FSEventStreamCallback = { _, info, eventCount, _, eventFlags, _ in
      guard let info else { return }
      let owner = Unmanaged<LibraryChangeMonitor>.fromOpaque(info).takeUnretainedValue()
      let rootChangedMask = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
      let mustScanMask = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
      let userDroppedMask = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
      let kernelDroppedMask = FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
      let idsWrappedMask = FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
      var rootChanged = false
      var mustRescan = false
      let flagsBuffer = UnsafeBufferPointer(start: eventFlags, count: eventCount)
      for flags in flagsBuffer {
        if flags & rootChangedMask != 0 { rootChanged = true }
        if flags & (mustScanMask | userDroppedMask | kernelDroppedMask | idsWrappedMask) != 0 {
          mustRescan = true
        }
      }
      let event = LibraryChangeEvent(rootChanged: rootChanged, mustRescan: mustRescan)
      Task { @MainActor in owner.onChange(event) }
    }

    let flags = FSEventStreamCreateFlags(
      UInt32(kFSEventStreamCreateFlagWatchRoot) | UInt32(kFSEventStreamCreateFlagIgnoreSelf))
    let paths = [root.path] as CFArray
    guard
      let stream = FSEventStreamCreate(
        nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
        flags)
    else {
      logger.error("Could not create FSEvents stream; using fallback scan timer")
      return false
    }

    self.stream = stream
    FSEventStreamSetDispatchQueue(stream, eventQueue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      logger.error("Could not start FSEvents stream; using fallback scan timer")
      return false
    }
    return true
  }

  @discardableResult
  func restart() -> Bool {
    stop()
    return start()
  }

  func stop() {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
  }
}

// SAFETY: the single mutable Bool is accessed only while holding `lock`. This
// small bridge exists solely for FileManager's synchronous enumeration callback.
private final class ScanFailureFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var failed = false
  func mark() {
    lock.lock()
    failed = true
    lock.unlock()
  }
  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return failed
  }
}

struct LibraryScanMetrics: Sendable, Equatable {
  var enumeratedFiles = 0
  var hashedFiles = 0
  var databaseTransactions = 0
  var completed = false
}

actor LibraryScanner {
  static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"]

  private let db: LibraryDatabase
  private let directories: AppDirectories
  private let hashFile: @Sendable (URL) async throws -> String
  private let metadataLoader: @Sendable (URL) async -> (duration: Double, title: String?)
  private let onError: @MainActor @Sendable (String) -> Void
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "Library")
  private var running = false
  private var rescanRequested = false
  private var scanTask: Task<Void, Never>?
  private var completions: [@MainActor @Sendable () -> Void] = []
  private var cleanedStaleImports = false
  private var shuttingDown = false
  private var lastMetrics = LibraryScanMetrics()

  init(
    db: LibraryDatabase, directories: AppDirectories = AppPaths.current,
    hashFile: @escaping @Sendable (URL) async throws -> String = sha256FileCancellable,
    metadataLoader: @escaping @Sendable (URL) async -> (duration: Double, title: String?) =
      audioMetadata,
    onError: @escaping @MainActor @Sendable (String) -> Void = { _ in }
  ) {
    self.db = db
    self.directories = directories
    self.hashFile = hashFile
    self.metadataLoader = metadataLoader
    self.onError = onError
  }

  func metrics() -> LibraryScanMetrics { lastMetrics }

  /// Deterministic integration-test seam; production callers use coalesced scan().
  func reconcileNow() async { await perform() }

  /// Public fire-and-forget entry point for UI/FSEvents callers. Actor
  /// isolation owns all coalescing state; callers never share mutable scanner
  /// state across executors.
  nonisolated func scan(completion: @escaping @MainActor @Sendable () -> Void) {
    Task { await self.enqueue(completion: completion) }
  }

  private func enqueue(completion: @escaping @MainActor @Sendable () -> Void) {
    // `scan()` bridges synchronous UI/FSEvents callers through an unstructured Task.
    // A request created just before confirmed termination can therefore reach this
    // actor after `cancelAndWait()` has begun. Never let that late request restart
    // reconciliation work during process shutdown.
    guard !shuttingDown else { return }
    completions.append(completion)
    if running {
      rescanRequested = true
      return
    }
    running = true
    scanTask = Task { [weak self] in
      await self?.scanLoop()
    }
  }

  /// Coalesce scan requests without dropping a filesystem event that arrives
  /// while a scan is already running. Every caller completes after the newest
  /// requested pass reaches a stable point.
  private func scanLoop() async {
    while true {
      await perform()

      if Task.isCancelled {
        rescanRequested = false
        completions.removeAll(keepingCapacity: true)
        running = false
        scanTask = nil
        return
      }

      if rescanRequested {
        rescanRequested = false
        continue
      }

      let callbacks = completions
      completions.removeAll(keepingCapacity: true)
      running = false
      scanTask = nil
      for callback in callbacks { await callback() }
      return
    }
  }

  /// Stop an in-flight reconciliation and wait until its owned hashing/metadata
  /// work has unwound. Confirmed application termination uses this so no scanner
  /// task is abandoned as the process shuts down.
  func cancelAndWait() async {
    shuttingDown = true
    rescanRequested = false
    completions.removeAll(keepingCapacity: true)
    let activeTask = scanTask
    activeTask?.cancel()
    if let activeTask { await activeTask.value }
    scanTask = nil
    running = false
  }

  private func enumerateAudioURLs(fileManager fm: FileManager, failure: ScanFailureFlag) -> [URL]? {
    guard
      let en = fm.enumerator(
        at: directories.library,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [],
        errorHandler: { _, _ in
          failure.mark()
          return true
        })
    else { return nil }

    var urls: [URL] = []
    var canonicalPaths = Set<String>()
    for case let candidate as URL in en {
      if Task.isCancelled { return nil }
      guard Self.audioExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
      let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
      // The extension filter is only a naming rule. A library directory can also
      // contain FIFOs, devices, or sockets whose names end in `.mp3`; passing one
      // to FileHandle for hashing can block before cooperative cancellation gets
      // another chance. Resolve first so links to regular audio remain supported,
      // then require the resolved entry to be a regular file.
      guard
        let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else { continue }
      var isDirectory: ObjCBool = false
      guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue,
        canonicalPaths.insert(resolved.path).inserted
      else { continue }
      urls.append(resolved)
    }
    urls.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    return urls
  }

  /// Interrupted imports can leave only Cuelixa's hidden staging name. Cleanup
  /// runs once on the scanner actor during startup, never on the AppKit thread.
  private func cleanupStaleImportFiles(fileManager fm: FileManager) {
    guard
      let contents = try? fm.contentsOfDirectory(
        at: directories.library, includingPropertiesForKeys: nil)
    else { return }
    for url in contents
    where url.lastPathComponent.hasPrefix(".cuelixa-import-") && url.pathExtension == "tmp" {
      do {
        try fm.removeItem(at: url)
      } catch {
        logger.error(
          "Could not remove stale import staging file: \(error.localizedDescription, privacy: .private)"
        )
      }
    }
  }

  private func perform() async {
    var metrics = LibraryScanMetrics()
    defer { lastMetrics = metrics }
    do {
      try directories.ensure()
    } catch {
      logger.error(
        "Could not prepare library directories: \(error.localizedDescription, privacy: .private)")
      await onError("The lesson library folders could not be prepared.")
      return
    }
    let fm = FileManager.default
    if !cleanedStaleImports {
      cleanupStaleImportFiles(fileManager: fm)
      cleanedStaleImports = true
    }
    if Task.isCancelled { return }
    let failure = ScanFailureFlag()
    guard let urls = enumerateAudioURLs(fileManager: fm, failure: failure), !Task.isCancelled else {
      if !Task.isCancelled { await onError("The lesson library could not be read.") }
      return
    }
    metrics.enumeratedFiles = urls.count
    guard let knownRecords = db.fileRecords() else {
      await onError("The library database could not load its previous scan state.")
      return
    }
    var scannedRecords: [ScannedFileRecord] = []
    scannedRecords.reserveCapacity(urls.count)
    let now = Date().timeIntervalSince1970
    for url in urls {
      if Task.isCancelled { return }
      guard let sig = fileSignature(url) else {
        failure.mark()
        continue
      }
      let path = url.path
      if let known = knownRecords[path], known.signature == sig {
        scannedRecords.append(
          .init(
            path: path, hash: known.hash, signature: sig,
            title: known.title, duration: known.duration))
        continue
      }
      let hash: String
      do {
        hash = try await hashFile(url)
        metrics.hashedFiles += 1
      } catch is CancellationError {
        return
      } catch {
        failure.mark()
        continue
      }
      if Task.isCancelled { return }
      let meta = await metadataLoader(url)
      if Task.isCancelled { return }
      guard fileSignature(url) == sig else {
        failure.mark()
        continue
      }
      let title = meta.title ?? humanizedTitle(url.deletingPathExtension().lastPathComponent)
      scannedRecords.append(
        .init(
          path: path, hash: hash, signature: sig, title: title, duration: meta.duration))
    }
    if failure.value {
      logger.error("Library scan was incomplete; stale-path reconciliation was deferred")
    }
    if !db.applyScan(scannedRecords, seenAt: now, complete: !failure.value) {
      logger.error("Library reconciliation failed")
      await onError("The library database could not save the latest scan.")
    } else {
      metrics.databaseTransactions = 1
      metrics.completed = !failure.value
      if failure.value {
        await onError(
          "Some lesson files could not be read. Unseen library entries were preserved.")
      }
    }
  }
}
