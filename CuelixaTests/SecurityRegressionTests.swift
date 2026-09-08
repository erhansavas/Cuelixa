// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Darwin
import Foundation
import Testing

private struct SecurityFixture {
  let root: URL
  let directories: AppDirectories

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CuelixaSecurityTests-\(UUID().uuidString)", isDirectory: true)
    directories = .isolated(root: root)
    try directories.ensure()
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Untrusted subtitle inputs", .serialized)
struct SubtitleSecurityTests {
  @Test("Entity parsing remains bounded with repeated unmatched ampersands")
  func repeatedEntities() {
    let text = String(repeating: "&", count: 100_000) + " &amp; &#65; &#x1F600;"
    let started = ContinuousClock.now
    let parsed = SRT.parse("1\n00:00:00,000 --> 00:00:01,000\n" + text)
    #expect(started.duration(to: .now) < .seconds(2))
    #expect(parsed.first?.text == String(repeating: "&", count: 100_000) + " & A 😀")
  }

  @Test("Long authored cues preserve all words without blocking playback")
  func longCue() {
    let source = Array(
      repeating: "A normal paragraph contains several spoken words.", count: 400
    ).joined(separator: " ")
    let started = ContinuousClock.now
    let balanced = SubtitleBalancer.balance(source)
    #expect(started.duration(to: .now) < .seconds(2))
    #expect(balanced.split(whereSeparator: \.isWhitespace) == source.split(separator: " "))
    #expect(balanced.split(separator: "\n").count == 3)
  }

  @Test("Nonfinite and unrepresentable times never trap formatting")
  func invalidTimes() {
    for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -1] {
      #expect(durationLabel(value) == "0:00")
      #expect(clockLabel(value) == "00:00")
      #expect(SRT.encode([.init(start: value, end: value, text: "Invalid")]).isEmpty)
    }
    #expect(clockLabel(3_661) == "1:01:01")
    #expect(durationLabel(3_661) == "1:01:01")
    let valid = [SubtitleCue(start: 3_661.125, end: 3_662.75, text: "Valid")]
    #expect(SRT.parse(SRT.encode(valid)) == valid)
    #expect(SubtitleBalancer.balance("one two three four five six", maxLineChars: 0) != "")
  }

  @Test("Oversized files are rejected before allocation; regular sidecar links still work")
  func boundedSidecarReads() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let oversized = fixture.root.appendingPathComponent("oversized.srt")
    #expect(FileManager.default.createFile(atPath: oversized.path, contents: nil))
    let file = try FileHandle(forWritingTo: oversized)
    try file.truncate(atOffset: UInt64(SRT.maximumFileBytes + 1))
    try file.close()
    #expect(SRT.parse(url: oversized).isEmpty)

    let target = fixture.root.appendingPathComponent("original.srt")
    let cue = SubtitleCue(start: 0, end: 1, text: "Authored subtitle")
    try Data(SRT.encode([cue]).utf8).write(to: target)
    let sidecar = fixture.directories.library.appendingPathComponent("lesson.srt")
    try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: target)
    #expect(SRT.parse(url: sidecar) == [cue])
    #expect(
      SRT.validSidecarURL(
        forAudioPath: fixture.directories.library.appendingPathComponent("lesson.wav").path)
        == sidecar)
  }

  @Test("Missing files, directories and FIFOs cannot be hashed as regular audio")
  func rejectsSpecialFiles() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    #expect(sha256File(fixture.root.appendingPathComponent("missing")) == nil)
    #expect(sha256File(fixture.root) == nil)
    let fifo = fixture.root.appendingPathComponent("pipe.srt")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    let started = ContinuousClock.now
    #expect(throws: Error.self) { try sha256FileCheckingCancellation(fifo) }
    #expect(SRT.parse(url: fifo).isEmpty)
    #expect(started.duration(to: .now) < .seconds(1))
  }
}

@Suite("Managed file boundaries", .serialized)
struct ManagedFileSecurityTests {
  @Test("Malformed content hashes cannot publish outside managed transcripts")
  func rejectsPathTraversal() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let cache = TranscriptCache(directories: fixture.directories)
    let cue = SubtitleCue(start: 0, end: 1, text: "Hello")
    for hash in [
      "../outside", "", "audio-hash", String(repeating: "a", count: 63),
      "../" + String(repeating: "b", count: 64),
    ] {
      #expect(cache.commit(hash: hash, cues: [cue]) == nil)
      #expect(cache.verifiedSRTURL(hash: hash) == nil)
    }
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.directories.support.appendingPathComponent("outside.srt").path))
    let validHash = String(repeating: "a", count: 64)
    #expect(cache.commit(hash: validHash, cues: [cue]) != nil)
    #expect(cache.verified(hash: validHash))
  }

  @Test("Transcript reset removes only managed artifacts and preserves unrelated content")
  func resetOwnership() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let fm = FileManager.default
    let cache = TranscriptCache(directories: fixture.directories)
    let hash = String(repeating: "a", count: 64)
    #expect(cache.commit(hash: hash, cues: [.init(start: 0, end: 1, text: "Generated")]) != nil)
    let note = fixture.directories.transcripts.appendingPathComponent("notes.txt")
    let authored = fixture.directories.library.appendingPathComponent("lesson.srt")
    let nested = fixture.directories.transcripts.appendingPathComponent(
      String(repeating: "b", count: 64) + ".srt", isDirectory: true)
    let link = fixture.directories.transcripts.appendingPathComponent(
      String(repeating: "c", count: 64) + ".srt")
    try Data("Notes".utf8).write(to: note)
    try Data("Authored".utf8).write(to: authored)
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("Keep".utf8).write(to: nested.appendingPathComponent("important.txt"))
    try fm.createSymbolicLink(at: link, withDestinationURL: authored)
    try cache.resetManagedTranscripts()
    #expect(!cache.verified(hash: hash))
    #expect(!fm.fileExists(atPath: cache.srtURL(hash: hash).path))
    #expect(!fm.fileExists(atPath: cache.manifestURL(hash: hash).path))
    #expect(try Data(contentsOf: note) == Data("Notes".utf8))
    #expect(try Data(contentsOf: authored) == Data("Authored".utf8))
    #expect(fm.fileExists(atPath: nested.appendingPathComponent("important.txt").path))
    #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == authored.path)
  }

  @Test("Cache verification rejects links whose target can change behind the memo")
  func cacheSymbolicLinks() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let cache = TranscriptCache(directories: fixture.directories)
    let hash = String(repeating: "a", count: 64)
    let target = fixture.root.appendingPathComponent("external.srt")
    let original = Data(SRT.encode([.init(start: 0, end: 1, text: "Hello")]).utf8)
    try original.write(to: target)
    try FileManager.default.createSymbolicLink(
      at: cache.srtURL(hash: hash), withDestinationURL: target)
    let manifest: [String: Any] = [
      "schema": 2, "audio_sha256": hash, "engine": "apple.speechtranscriber",
      "srt_sha256": SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(),
    ]
    try JSONSerialization.data(withJSONObject: manifest).write(to: cache.manifestURL(hash: hash))
    #expect(!cache.verified(hash: hash))
    try Data(SRT.encode([.init(start: 0, end: 1, text: "Altered")]).utf8).write(to: target)
    #expect(!cache.verified(hash: hash))
  }

  @Test("Publishing replaces final links without touching their targets")
  func commitReplacesFinalLinks() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let cache = TranscriptCache(directories: fixture.directories)
    let hash = String(repeating: "b", count: 64)
    let externalSRT = fixture.root.appendingPathComponent("external.srt")
    let externalManifest = fixture.root.appendingPathComponent("external.json")
    try Data("keep this file".utf8).write(to: externalSRT)
    try Data("keep this manifest".utf8).write(to: externalManifest)
    try FileManager.default.createSymbolicLink(
      at: cache.srtURL(hash: hash), withDestinationURL: externalSRT)
    try FileManager.default.createSymbolicLink(
      at: cache.manifestURL(hash: hash), withDestinationURL: externalManifest)

    #expect(cache.commit(hash: hash, cues: [.init(start: 0, end: 1, text: "Published")]) != nil)
    #expect(LocalFileAccess.isRegularFile(cache.srtURL(hash: hash)))
    #expect(LocalFileAccess.isRegularFile(cache.manifestURL(hash: hash)))
    #expect(try Data(contentsOf: externalSRT) == Data("keep this file".utf8))
    #expect(try Data(contentsOf: externalManifest) == Data("keep this manifest".utf8))
  }

  @Test("Rapid same-size replacements invalidate verified transcript state")
  func modifiedCache() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let cache = TranscriptCache(directories: fixture.directories)
    let hash = String(repeating: "a", count: 64)
    let url = try #require(
      cache.commit(
        hash: hash, cues: [.init(start: 0, end: 1, text: "Hello")]))
    #expect(cache.verified(hash: hash))
    try Data(SRT.encode([.init(start: 0, end: 1, text: "Other")]).utf8).write(
      to: url, options: .atomic)
    #expect(!cache.verified(hash: hash))
    #expect(cache.commit(hash: hash, cues: [.init(start: 0, end: 1, text: "Repaired")]) != nil)
    #expect(cache.verified(hash: hash))
  }

  @Test("Managed directories are private and cannot be replaced by links")
  func privateDirectories() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let fm = FileManager.default
    try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: fixture.directories.library.path)
    try fixture.directories.ensure()
    for directory in [
      fixture.directories.support, fixture.directories.cache,
      fixture.directories.transcripts, fixture.directories.staging,
    ] {
      let attrs = try fm.attributesOfItem(atPath: directory.path)
      #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
    #expect(
      (try fm.attributesOfItem(atPath: fixture.directories.library.path)[.posixPermissions]
        as? NSNumber)?.intValue == 0o750)
    let target = fixture.root.appendingPathComponent("unrelated", isDirectory: true)
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    try fm.removeItem(at: fixture.directories.transcripts)
    try fm.createSymbolicLink(at: fixture.directories.transcripts, withDestinationURL: target)
    #expect(throws: Error.self) { try fixture.directories.ensure() }
    #expect(throws: Error.self) {
      try TranscriptCache(directories: fixture.directories).resetManagedTranscripts()
    }
    #expect(try fm.contentsOfDirectory(atPath: target.path).isEmpty)
  }

  @Test("Database links and corrupt databases are rejected without replacing data")
  func databaseRecoveryBoundary() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let target = fixture.root.appendingPathComponent("original.sqlite3")
    let original = Data("This is not a database. Preserve it for recovery.".utf8)
    try original.write(to: target)
    try FileManager.default.createSymbolicLink(
      at: fixture.directories.database, withDestinationURL: target)
    #expect(LibraryDatabase(url: fixture.directories.database).initializationError != nil)
    #expect(try Data(contentsOf: target) == original)
    #expect(LibraryDatabase(url: target).initializationError != nil)
    #expect(try Data(contentsOf: target) == original)
  }

  @Test("Startup cleanup preserves live imports and names that are not owned staging files")
  func importCleanupLease() async throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let fm = FileManager.default
    let library = fixture.directories.library
    let userFolder = library.appendingPathComponent(".cuelixa-import-not-staging.tmp")
    try fm.createDirectory(at: userFolder, withIntermediateDirectories: true)
    let note = userFolder.appendingPathComponent("notes.txt")
    try Data("Keep".utf8).write(to: note)
    let staging = library.appendingPathComponent(".cuelixa-import-\(UUID().uuidString).tmp")
    let database = LibraryDatabase(url: fixture.directories.database)
    let scanner = LibraryScanner(db: database, directories: fixture.directories)
    do {
      let lease = try #require(try LibraryImportLease.acquire(at: library))
      defer { withExtendedLifetime(lease) {} }
      try Data("Active copy".utf8).write(to: staging)
      await scanner.reconcileNow()
      #expect(fm.fileExists(atPath: staging.path))
    }
    await scanner.reconcileNow()
    #expect(!fm.fileExists(atPath: staging.path))
    #expect(try Data(contentsOf: note) == Data("Keep".utf8))
  }
}

@Suite("Library persistence and search", .serialized)
struct PersistenceRegressionTests {
  @Test("Search handles Unicode and literal wildcard characters")
  func nativeSearch() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let database = LibraryDatabase(url: fixture.directories.database)
    let titles = ["CAFÉ Lesson", "КИРИЛЛИЦА", "100% Listening", "under_score"]
    let records = titles.enumerated().map { index, title in
      ScannedFileRecord(
        path: "/fixture/\(index).wav", hash: "h\(index)",
        signature: .init(size: 1, mtimeNS: 1, ctimeNS: 1), title: title, duration: 60)
    }
    #expect(database.applyScan(records, seenAt: 1, complete: true))
    #expect(database.tracks(section: .all, query: "cafe").map(\.title) == [titles[0]])
    #expect(database.tracks(section: .all, query: "кириллица").map(\.title) == [titles[1]])
    #expect(database.tracks(section: .all, query: "%").map(\.title) == [titles[2]])
    #expect(database.tracks(section: .all, query: "_").map(\.title) == [titles[3]])
  }

  @Test("Renaming a lesson preserves resume and completion after reopening the database")
  func reopenAndRename() throws {
    let fixture = try SecurityFixture()
    defer { fixture.remove() }
    let hash = String(repeating: "a", count: 64)
    var record = ScannedFileRecord(
      path: "/fixture/original.wav", hash: hash,
      signature: .init(size: 1, mtimeNS: 1, ctimeNS: 1), title: "Lesson", duration: 60)
    do {
      let database = LibraryDatabase(url: fixture.directories.database)
      #expect(database.applyScan([record], seenAt: 1, complete: true))
      #expect(database.setPosition(hash: hash, position: 25))
    }
    let reopened = LibraryDatabase(url: fixture.directories.database)
    #expect(reopened.track(hash: hash)?.position == 25)
    record = .init(
      path: "/fixture/renamed.wav", hash: hash, signature: record.signature,
      title: "Renamed", duration: 60)
    #expect(reopened.applyScan([record], seenAt: 2, complete: true))
    #expect(reopened.track(hash: hash)?.position == 25)
    #expect(reopened.track(hash: hash)?.path == record.path)
    #expect(reopened.markCompleted(hash: hash, completed: true))
    let anotherConnection = LibraryDatabase(url: fixture.directories.database)
    #expect(anotherConnection.track(hash: hash)?.completed == true)
    #expect(anotherConnection.track(hash: hash)?.position == 0)
  }
}
