// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import XCTest

private func temporaryRoot(_ name: String = #function) throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "CuelixaTests-\(name)-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private actor HashCounter {
  private enum HashError: Error { case unreadable }
  private var count = 0

  func hash(_ url: URL) throws -> String {
    count += 1
    guard let value = sha256File(url) else { throw HashError.unreadable }
    return value
  }

  func value() -> Int { count }
  func reset() { count = 0 }
}

private actor FakeTranscriptionExecutor: TranscriptionExecuting {
  private var continuation: CheckedContinuation<Void, Never>?
  private var releaseRequested = false
  private var calls = 0
  private var cancellations = 0

  func transcribe(
    snapshot _: URL, duration _: Double,
    progress: @escaping @MainActor @Sendable (String, Int?) -> Void
  ) async throws -> [SubtitleCue] {
    calls += 1
    await progress("Fake transcription", 50)
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if releaseRequested {
          releaseRequested = false
          continuation.resume()
        } else {
          self.continuation = continuation
        }
      }
    } onCancel: {
      Task { await self.release() }
    }
    try Task.checkCancellation()
    return [SubtitleCue(start: 0, end: 1, text: "Hello")]
  }

  func cancelAndWait() async {
    cancellations += 1
    release()
  }

  func release() {
    if let continuation {
      self.continuation = nil
      continuation.resume()
    } else {
      releaseRequested = true
    }
  }

  func callCount() -> Int { calls }
  func cancellationCount() -> Int { cancellations }
}

@MainActor
private func waitUntil(
  timeout: Duration = .seconds(3), _ condition: @escaping @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("Timed out waiting for asynchronous state")
}

@Suite("Library path resolution")
struct LibraryPathTests {
  @Test("A clean install uses the home Music directory")
  func cleanInstall() throws {
    let home = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: home) }
    let directories = AppDirectories.resolve(home: home)
    #expect(
      directories.library
        == home.appendingPathComponent("Music/Cuelixa", isDirectory: true))
  }

  @Test("A regular legacy directory remains selected")
  func validLegacyDirectory() throws {
    let home = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: home) }
    let legacy = home.appendingPathComponent("podcast", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let directories = AppDirectories.resolve(home: home)
    #expect(directories.library == legacy)
    #expect(directories.legacyLibraryIssue == nil)
  }

  @Test("A legacy file is rejected")
  func legacyFile() throws {
    let home = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: home) }
    let legacy = home.appendingPathComponent("podcast")
    try Data("not a directory".utf8).write(to: legacy)
    let directories = AppDirectories.resolve(home: home)
    #expect(directories.library != legacy)
    #expect(directories.legacyLibraryIssue == .notDirectory)
  }

  @Test("A legacy symbolic link is never followed automatically")
  func legacySymbolicLink() throws {
    let home = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: home) }
    let target = home.appendingPathComponent("actual", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let legacy = home.appendingPathComponent("podcast")
    try FileManager.default.createSymbolicLink(at: legacy, withDestinationURL: target)
    let directories = AppDirectories.resolve(home: home)
    #expect(directories.library != legacy)
    #expect(directories.legacyLibraryIssue == .symbolicLink)
  }

  @Test("An inaccessible legacy directory is rejected")
  func inaccessibleLegacyDirectory() throws {
    let home = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: home) }
    let legacy = home.appendingPathComponent("podcast", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o400], atPath: legacy.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], atPath: legacy.path)
    }
    let directories = AppDirectories.resolve(home: home)
    #expect(directories.library != legacy)
    #expect(directories.legacyLibraryIssue == .inaccessible)
  }

  @Test("Directory creation failure is never swallowed")
  func directoryCreationFailure() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("blocks Music directory".utf8).write(to: root.appendingPathComponent("Music"))
    let directories = AppDirectories.isolated(root: root)
    #expect(throws: Error.self) { try directories.ensure() }
  }

  @Test("A read-only library fails directory validation")
  func readOnlyLibrary() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], atPath: directories.library.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], atPath: directories.library.path)
    }
    #expect(throws: Error.self) { try directories.ensure() }
  }
}

@Suite("Safe imports", .serialized)
struct ImportCoordinatorTests {
  @Test("Concurrent same-basename drops receive distinct destinations")
  func concurrentSameName() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    let firstSource = root.appendingPathComponent("source-a", isDirectory: true)
    let secondSource = root.appendingPathComponent("source-b", isDirectory: true)
    try FileManager.default.createDirectory(at: firstSource, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
    let first = firstSource.appendingPathComponent("lesson.mp3")
    let second = secondSource.appendingPathComponent("lesson.mp3")
    try Data("first audio".utf8).write(to: first)
    try Data("second audio".utf8).write(to: second)
    let coordinator = ImportCoordinator(directories: directories)

    async let a = coordinator.importFiles([first])
    async let b = coordinator.importFiles([second])
    let summaries = await [a, b]
    #expect(summaries.reduce(0) { $0 + $1.count(.imported) } == 2)
    let imported = try FileManager.default.contentsOfDirectory(
      at: directories.library, includingPropertiesForKeys: nil
    )
    .filter { !$0.lastPathComponent.hasPrefix(".") }
    #expect(Set(imported.map(\.lastPathComponent)) == ["lesson.mp3", "lesson (2).mp3"])
    #expect(try Data(contentsOf: first) == Data("first audio".utf8))
    #expect(try Data(contentsOf: second) == Data("second audio".utf8))
  }

  @Test("An identical destination is reported as duplicate")
  func duplicate() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    let source = root.appendingPathComponent("source.mp3")
    let data = Data("same audio".utf8)
    try data.write(to: source)
    try data.write(to: directories.library.appendingPathComponent("source.mp3"))
    let summary = await ImportCoordinator(directories: directories).importFiles([source])
    #expect(summary.count(.duplicate) == 1)
    #expect(summary.count(.imported) == 0)
  }

  @Test("Unsupported inputs are explicit")
  func unsupported() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("notes.txt")
    try Data("notes".utf8).write(to: source)
    let summary = await ImportCoordinator(directories: .isolated(root: root)).importFiles([source])
    #expect(summary.count(.unsupported) == 1)
  }

  @Test("Cancellation reports every input and leaves no staging file")
  func cancellationCleanup() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    let source = root.appendingPathComponent("large.mp3")
    try Data(repeating: 0x5A, count: 16 * 1_024 * 1_024).write(to: source)
    let coordinator = ImportCoordinator(directories: directories)
    let task = Task { await coordinator.importFiles([source]) }
    task.cancel()
    let summary = await task.value
    #expect(summary.count(.cancelled) == 1)
    let contents = try FileManager.default.contentsOfDirectory(
      at: directories.library, includingPropertiesForKeys: nil)
    #expect(!contents.contains { $0.lastPathComponent.hasPrefix(".cuelixa-import-") })
  }

  @Test("A directory disguised with an audio extension fails explicitly")
  func invalidSource() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("folder.mp3", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let summary = await ImportCoordinator(directories: .isolated(root: root)).importFiles([source])
    #expect(summary.count(.failed) == 1)
  }
}

@Suite("Batched database reconciliation", .serialized)
struct DatabaseBatchTests {
  @Test("A partial scan never marks unseen tracks missing")
  func partialScanPreservesState() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let db = LibraryDatabase(url: root.appendingPathComponent("library.sqlite3"))
    let record = ScannedFileRecord(
      path: root.appendingPathComponent("lesson.mp3").path, hash: "abc",
      signature: .init(size: 10, mtimeNS: 1, ctimeNS: 1), title: "Lesson", duration: 10)
    #expect(db.applyScan([record], seenAt: 1, complete: true))
    #expect(db.applyScan([], seenAt: 2, complete: false))
    #expect(db.track(hash: "abc")?.missing == false)
  }

  @Test("One thousand unchanged records round-trip through one batch")
  func thousandRecords() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let db = LibraryDatabase(url: root.appendingPathComponent("library.sqlite3"))
    let records = (0..<1_000).map { index in
      ScannedFileRecord(
        path: root.appendingPathComponent("\(index).mp3").path, hash: "hash-\(index)",
        signature: .init(size: Int64(index + 1), mtimeNS: 1, ctimeNS: 1),
        title: "Lesson \(index)", duration: 60)
    }
    #expect(db.applyScan(records, seenAt: 1, complete: true))
    #expect(db.fileRecords()?.count == 1_000)
    #expect(db.applyScan(records, seenAt: 2, complete: true))
    #expect(db.fileRecords()?.count == 1_000)
  }

  @Test("A failed batch rolls back every write")
  func rollback() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let db = LibraryDatabase(url: root.appendingPathComponent("library.sqlite3"))
    let original = ScannedFileRecord(
      path: root.appendingPathComponent("original.mp3").path, hash: "original",
      signature: .init(size: 1, mtimeNS: 1, ctimeNS: 1), title: "Original", duration: 1)
    let replacement = ScannedFileRecord(
      path: root.appendingPathComponent("replacement.mp3").path, hash: "replacement",
      signature: .init(size: 2, mtimeNS: 2, ctimeNS: 2), title: "Replacement", duration: 2)
    #expect(db.applyScan([original], seenAt: 1, complete: true))
    #expect(
      !db.applyScan(
        [replacement], seenAt: 2, complete: true, failAfterRecordForTesting: 1))
    #expect(db.fileRecords()?.keys.sorted() == [original.path])
    #expect(db.track(hash: "original")?.missing == false)
    #expect(db.track(hash: "replacement") == nil)
  }
}

@Suite("Scanner batching", .serialized)
struct ScannerBatchTests {
  @Test("One thousand unchanged files perform zero hashes and one transaction")
  func unchangedFiles() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    for index in 0..<1_000 {
      try Data("audio-\(index)".utf8).write(
        to: directories.library.appendingPathComponent("\(index).mp3"))
    }

    let counter = HashCounter()
    let database = LibraryDatabase(url: directories.database)
    let scanner = LibraryScanner(
      db: database, directories: directories,
      hashFile: { url in try await counter.hash(url) },
      metadataLoader: { _ in (duration: 1, title: nil) })

    await scanner.reconcileNow()
    let initialHashCount = await counter.value()
    let initialMetrics = await scanner.metrics()
    #expect(initialHashCount == 1_000)
    #expect(initialMetrics.databaseTransactions == 1)
    #expect(initialMetrics.completed)

    await counter.reset()
    await scanner.reconcileNow()
    let unchangedMetrics = await scanner.metrics()
    let unchangedHashCount = await counter.value()
    #expect(unchangedHashCount == 0)
    #expect(unchangedMetrics.hashedFiles == 0)
    #expect(unchangedMetrics.databaseTransactions == 1)
    #expect(unchangedMetrics.completed)

    try Data("changed audio payload".utf8).write(
      to: directories.library.appendingPathComponent("500.mp3"))
    await counter.reset()
    await scanner.reconcileNow()
    let changedMetrics = await scanner.metrics()
    let changedHashCount = await counter.value()
    #expect(changedHashCount == 1)
    #expect(changedMetrics.hashedFiles == 1)
    #expect(changedMetrics.databaseTransactions == 1)
    #expect(changedMetrics.completed)
  }
}

@Suite("Transcript cache integrity", .serialized)
struct TranscriptCacheTests {
  @Test("Half-written and mismatched transcript pairs are rejected")
  func rejectsInvalidPairs() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    let cache = TranscriptCache(directories: directories)
    let hash = "audio-hash"
    let srt = cache.srtURL(hash: hash)
    let manifest = cache.manifestURL(hash: hash)
    try "1\n00:00:00,000 --> 00:00:01,000\nHello\n".write(
      to: srt, atomically: true, encoding: .utf8)
    #expect(cache.verifiedSRTURL(hash: hash) == nil)

    let invalidManifest: [String: Any] = [
      "schema": 2, "audio_sha256": hash, "srt_sha256": "wrong",
      "engine": "apple.speechtranscriber", "locale": "en-US",
    ]
    try JSONSerialization.data(withJSONObject: invalidManifest).write(
      to: manifest, options: .atomic)
    #expect(cache.verifiedSRTURL(hash: hash) == nil)
  }
}

@Suite("Transcription queue", .serialized)
@MainActor
struct TranscriptionQueueTests {
  @Test("Shared-hash watchers cancel independently")
  func independentWatcherCancellation() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    let audio = root.appendingPathComponent("lesson.mp3")
    try Data("stable audio".utf8).write(to: audio)
    let hash = try #require(sha256File(audio))
    let track = Track(
      contentHash: hash, title: "Lesson", duration: 1, position: 0, completed: false,
      completedAt: nil, lastPlayedAt: nil, addedAt: 0, lastSeenAt: 0, missing: false,
      path: audio.path)
    let executor = FakeTranscriptionExecutor()
    let transcriber = NativeTranscriber(
      cache: TranscriptCache(directories: directories), stagingDirectory: directories.staging,
      executor: executor)
    var firstResult: Result<URL, Error>?
    var secondResult: Result<URL, Error>?
    let firstToken = try #require(
      transcriber.request(
        track: track, progress: { _, _ in }, completion: { firstResult = $0 }))
    _ = try #require(
      transcriber.request(
        track: track, progress: { _, _ in }, completion: { secondResult = $0 }))

    try await waitUntil { transcriber.currentHash == hash }
    #expect(transcriber.cancel(hash: hash, token: firstToken))
    if case .failure(let error) = firstResult {
      #expect((error as? CuelixaError) == .cancelled)
    } else {
      Issue.record("First watcher did not receive cancellation")
    }
    await executor.release()
    try await waitUntil { secondResult != nil }
    if case .success(let url) = secondResult {
      #expect(FileManager.default.fileExists(atPath: url.path))
    } else {
      Issue.record("Second watcher did not complete successfully")
    }
    let callCount = await executor.callCount()
    let cancellationCount = await executor.cancellationCount()
    #expect(callCount == 1)
    #expect(cancellationCount == 0)
  }

  @Test("Final watcher cancellation stops the executor and drains on quit")
  func finalWatcherCancellation() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = AppDirectories.isolated(root: root)
    try directories.ensure()
    let audio = root.appendingPathComponent("lesson.mp3")
    try Data("stable audio".utf8).write(to: audio)
    let hash = try #require(sha256File(audio))
    let track = Track(
      contentHash: hash, title: "Lesson", duration: 1, position: 0, completed: false,
      completedAt: nil, lastPlayedAt: nil, addedAt: 0, lastSeenAt: 0, missing: false,
      path: audio.path)
    let executor = FakeTranscriptionExecutor()
    let transcriber = NativeTranscriber(
      cache: TranscriptCache(directories: directories), stagingDirectory: directories.staging,
      executor: executor)
    var result: Result<URL, Error>?
    let token = try #require(
      transcriber.request(track: track, progress: { _, _ in }, completion: { result = $0 }))
    try await waitUntil { transcriber.currentHash == hash }
    #expect(transcriber.cancel(hash: hash, token: token))
    await transcriber.cancelAllAndWait()
    if case .failure(let error) = result {
      #expect((error as? CuelixaError) == .cancelled)
    } else {
      Issue.record("Cancelled watcher did not receive cancellation")
    }
    let cancellationCount = await executor.cancellationCount()
    #expect(cancellationCount >= 1)
    #expect(transcriber.pendingCount == 0)
    #expect(!transcriber.isActive)
  }
}

final class CuelixaPerformanceTests: XCTestCase {
  func testScannerDatabaseBatchMedianIsNotWorseThanLegacyPerFileTransactions() throws {
    let records = (0..<1_000).map { index in
      ScannedFileRecord(
        path: "/fixture/\(index).mp3", hash: "hash-\(index)",
        signature: .init(size: Int64(index + 1), mtimeNS: 1, ctimeNS: 1),
        title: "Lesson \(index)", duration: 60)
    }
    var legacyDurations: [Duration] = []
    var batchDurations: [Duration] = []
    let clock = ContinuousClock()

    for sample in 0..<3 {
      let root = try temporaryRoot("legacy-\(sample)")
      defer { try? FileManager.default.removeItem(at: root) }
      let database = LibraryDatabase(url: root.appendingPathComponent("library.sqlite3"))
      let start = clock.now
      for record in records {
        _ = database.fileSignature(path: record.path)
        XCTAssertTrue(
          database.upsertFile(
            path: record.path, hash: record.hash, signature: record.signature,
            title: record.title, duration: record.duration, seenAt: 1))
      }
      XCTAssertTrue(database.reconcile(seenPaths: Set(records.map(\.path))))
      legacyDurations.append(start.duration(to: clock.now))
    }

    for sample in 0..<3 {
      let root = try temporaryRoot("batch-\(sample)")
      defer { try? FileManager.default.removeItem(at: root) }
      let database = LibraryDatabase(url: root.appendingPathComponent("library.sqlite3"))
      let start = clock.now
      _ = database.fileRecords()
      XCTAssertTrue(database.applyScan(records, seenAt: 1, complete: true))
      batchDurations.append(start.duration(to: clock.now))
    }

    let legacyMedian = legacyDurations.sorted()[1]
    let batchMedian = batchDurations.sorted()[1]
    XCTAssertLessThanOrEqual(batchMedian, legacyMedian)
  }

  func testTenThousandCueLookups() {
    let cues = (0..<10_000).map { index in
      SubtitleCue(start: Double(index), end: Double(index) + 0.8, text: "Cue \(index)")
    }
    let prefix = SubtitleTimeline.prefixMaximumEnds(for: cues)
    measure(metrics: [
      XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric(), XCTStorageMetric(),
    ]) {
      for index in stride(from: 0, to: 10_000, by: 3) {
        _ = SubtitleTimeline.activeCueIndex(
          in: cues, prefixMaximumEnds: prefix,
          at: Double(index) + 0.2)
      }
    }
  }
}
