// SPDX-License-Identifier: Apache-2.0
import CoreServices
import Foundation

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
  private let onChange: @MainActor (LibraryChangeEvent) -> Void
  private let eventQueue = DispatchQueue(
    label: "io.github.erhansavas.Cuelixa.library-events", qos: .utility)
  private var stream: FSEventStreamRef?

  init(onChange: @escaping @MainActor (LibraryChangeEvent) -> Void) {
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
    let paths = [AppPaths.library.path] as CFArray
    guard
      let stream = FSEventStreamCreate(
        nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
        flags)
    else {
      NSLog("Cuelixa: could not create library FSEvents stream; using fallback scan timer")
      return false
    }

    self.stream = stream
    FSEventStreamSetDispatchQueue(stream, eventQueue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      NSLog("Cuelixa: could not start library FSEvents stream; using fallback scan timer")
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

actor LibraryScanner {
  static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"]

  private let db: LibraryDatabase
  private var running = false
  private var rescanRequested = false
  private var scanTask: Task<Void, Never>?
  private var completions: [@MainActor @Sendable () -> Void] = []
  private var cleanedStaleImports = false
  private var shuttingDown = false

  init(db: LibraryDatabase) { self.db = db }

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
        at: AppPaths.library, includingPropertiesForKeys: [.isRegularFileKey],
        options: [],
        errorHandler: { _, _ in
          failure.mark()
          return true
        })
    else { return nil }

    var urls: [URL] = []
    for case let candidate as URL in en {
      if Task.isCancelled { return nil }
      guard Self.audioExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
      let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
      var isDirectory: ObjCBool = false
      guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue
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
        at: AppPaths.library, includingPropertiesForKeys: nil)
    else { return }
    for url in contents
    where url.lastPathComponent.hasPrefix(".cuelixa-import-") && url.pathExtension == "tmp" {
      do {
        try fm.removeItem(at: url)
      } catch {
        NSLog("Cuelixa: could not remove stale import staging file: %@", error.localizedDescription)
      }
    }
  }

  private func perform() async {
    try? AppPaths.ensure()
    let fm = FileManager.default
    if !cleanedStaleImports {
      cleanupStaleImportFiles(fileManager: fm)
      cleanedStaleImports = true
    }
    if Task.isCancelled { return }
    let failure = ScanFailureFlag()
    guard let urls = enumerateAudioURLs(fileManager: fm, failure: failure), !Task.isCancelled else {
      return
    }
    var seen = Set<String>()
    let now = Date().timeIntervalSince1970
    for url in urls {
      if Task.isCancelled { return }
      guard let sig = fileSignature(url) else {
        failure.mark()
        continue
      }
      let path = url.path
      if let known = db.fileSignature(path: path), known.1 == sig,
        let track = db.existingTrack(hash: known.0)
      {
        if db.upsertFile(
          path: path, hash: known.0, signature: sig, title: track.title,
          duration: track.duration, seenAt: now)
        {
          seen.insert(path)
        } else {
          failure.mark()
        }
        continue
      }
      let hash: String
      do {
        hash = try await sha256FileCancellable(url)
      } catch is CancellationError {
        return
      } catch {
        failure.mark()
        continue
      }
      if Task.isCancelled { return }
      let meta = await audioMetadata(url)
      if Task.isCancelled { return }
      guard fileSignature(url) == sig else {
        failure.mark()
        continue
      }
      let title = meta.title ?? humanizedTitle(url.deletingPathExtension().lastPathComponent)
      if db.upsertFile(
        path: path, hash: hash, signature: sig, title: title,
        duration: meta.duration, seenAt: now)
      {
        seen.insert(path)
      } else {
        failure.mark()
      }
    }
    if failure.value {
      NSLog("Cuelixa: library scan was incomplete; stale-path reconciliation was deferred")
    } else if !db.reconcile(seenPaths: seen) {
      NSLog("Cuelixa: library reconciliation failed")
    }
  }
}
