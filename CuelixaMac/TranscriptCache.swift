// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Darwin
import Foundation
import OSLog

/// Serializes broad transcript availability verification away from MainActor.
actor TranscriptAvailabilityWorker {
  private let cache: TranscriptCache

  init(cache: TranscriptCache) { self.cache = cache }

  func verifiedHashes(_ tracks: [Track]) -> Set<String> {
    var result = Set<String>()
    result.reserveCapacity(tracks.count)
    for track in tracks {
      if Task.isCancelled { return result }
      if cache.verifiedSRTURL(hash: track.contentHash) != nil
        || SRT.validSidecarURL(forAudioPath: track.path) != nil
      {
        result.insert(track.contentHash)
      }
    }
    cache.pruneVerificationMemo(keeping: Set(tracks.map(\.contentHash)))
    return result
  }
}

// SAFETY: cache reads, publication, reset and memo access are serialized by
// accessLock. The recursive lock permits commit to verify its published pair.
final class TranscriptCache: @unchecked Sendable {
  private let logger = Logger(
    subsystem: "io.github.erhansavas.Cuelixa", category: "TranscriptCache")
  private let directories: AppDirectories
  private struct Signature: Equatable {
    let srtSize: UInt64
    let srtMTimeNS: Int64
    let srtCTimeNS: Int64
    let manifestSize: UInt64
    let manifestMTimeNS: Int64
    let manifestCTimeNS: Int64
  }

  private struct MemoKey: Hashable {
    let hash: String
    let sourcePath: String
  }

  private struct Pair {
    let srt: URL
    let manifest: URL
  }

  private let accessLock = NSRecursiveLock()
  private var verifiedMemo: [MemoKey: (Signature, URL?)] = [:]

  init(directories: AppDirectories = AppPaths.current) { self.directories = directories }

  /// Preferred durable transcript URL. Call verifiedSRTURL when opening an
  /// existing transcript because the legacy cache-resident output is still supported.
  func srtURL(hash: String) -> URL {
    directories.transcripts.appendingPathComponent(hash + ".srt")
  }

  func manifestURL(hash: String) -> URL {
    directories.transcripts.appendingPathComponent(hash + ".json")
  }

  private func legacySRTURL(hash: String) -> URL {
    directories.legacySubtitles.appendingPathComponent(hash + ".srt")
  }

  private func legacyManifestURL(hash: String) -> URL {
    directories.legacySubtitles.appendingPathComponent(hash + ".json")
  }

  func verified(hash: String) -> Bool { verifiedSRTURL(hash: hash) != nil }

  /// Returns the exact verified SRT that should be played. Durable output
  /// wins; a valid legacy cache pair remains readable non-destructively.
  func verifiedSRTURL(hash: String) -> URL? {
    guard Self.isContentHash(hash) else { return nil }
    accessLock.lock()
    defer { accessLock.unlock() }
    let candidates = [
      Pair(srt: srtURL(hash: hash), manifest: manifestURL(hash: hash)),
      Pair(srt: legacySRTURL(hash: hash), manifest: legacyManifestURL(hash: hash)),
    ]

    for pair in candidates {
      guard let signature = signature(pair: pair) else { continue }
      let key = MemoKey(hash: hash, sourcePath: pair.srt.path)
      if let memo = verifiedMemo[key], memo.0 == signature {
        let cached = memo.1
        if let cached { return cached }
        continue
      }

      let result = verify(hash: hash, pair: pair) ? pair.srt : nil
      guard self.signature(pair: pair) == signature else { continue }
      verifiedMemo[key] = (signature, result)
      if let result { return result }
    }

    return nil
  }

  func pruneVerificationMemo(keeping hashes: Set<String>) {
    accessLock.lock()
    defer { accessLock.unlock() }
    verifiedMemo = verifiedMemo.filter { hashes.contains($0.key.hash) }
  }

  /// Deletes only subtitle artifacts owned by Cuelixa. User-owned sidecar SRT
  /// files beside lesson audio are intentionally outside these directories and
  /// are never touched by this maintenance action.
  func resetManagedTranscripts() throws {
    accessLock.lock()
    defer {
      verifiedMemo.removeAll(keepingCapacity: false)
      accessLock.unlock()
    }
    try directories.ensure()
    let fm = FileManager.default
    var ownedFiles: [URL] = []
    for directory in [directories.transcripts, directories.legacySubtitles] {
      guard (try? fm.attributesOfItem(atPath: directory.path)) != nil else { continue }
      try LocalFileAccess.ensurePrivateDirectory(directory)
      for item in try fm.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
      ) {
        guard ["srt", "json"].contains(item.pathExtension),
          Self.isContentHash(item.deletingPathExtension().lastPathComponent),
          LocalFileAccess.isRegularFile(item)
        else { continue }
        ownedFiles.append(item)
      }
    }
    for item in ownedFiles {
      // unlink never recursively removes a directory, even if a file changes
      // type between the check and deletion. Other names and links are kept.
      guard unlink(item.path) == 0 || errno == ENOENT else { throw LocalFileAccess.posixError() }
    }
  }

  /// Publishes newly generated transcripts to durable Application Support.
  /// The SRT is committed before the manifest; verification requires both files
  /// and matching hashes, so an interrupted write can never look valid.
  func commit(hash: String, cues: [SubtitleCue]) -> URL? {
    guard Self.isContentHash(hash), !cues.isEmpty else { return nil }
    accessLock.lock()
    defer { accessLock.unlock() }
    do {
      try directories.ensure()
    } catch {
      logger.error(
        "Could not prepare transcript directories: \(error.localizedDescription, privacy: .private)"
      )
      return nil
    }
    let dest = srtURL(hash: hash)
    let manifestDest = manifestURL(hash: hash)
    // Stage beside the destination so atomic rename also works when the cache
    // and Application Support directories live on different volumes.
    let stage = directories.transcripts.appendingPathComponent(".\(UUID().uuidString).srt")
    let manifestStage = directories.transcripts.appendingPathComponent(".\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: stage) }
    defer { try? FileManager.default.removeItem(at: manifestStage) }

    do {
      guard let encoded = SRT.encode(cues).data(using: .utf8),
        !encoded.isEmpty, encoded.count <= SRT.maximumFileBytes
      else { return nil }
      try encoded.write(to: stage, options: .atomic)
      guard LocalFileAccess.isRegularFile(stage), SRT.validate(url: stage) else { return nil }

      try LocalFileAccess.replaceAtomically(staged: stage, destination: dest)
      let subtitleHash = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()

      let manifest: [String: Any] = [
        "schema": 2,
        "audio_sha256": hash,
        "srt_sha256": subtitleHash,
        "engine": "apple.speechtranscriber",
        "locale": "en-US",
        "created_at": Date().timeIntervalSince1970,
      ]
      let data = try JSONSerialization.data(
        withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: manifestStage, options: .atomic)
      try LocalFileAccess.replaceAtomically(staged: manifestStage, destination: manifestDest)

      verifiedMemo = verifiedMemo.filter { $0.key.hash != hash }
      return verifiedSRTURL(hash: hash)
    } catch {
      logger.error("Could not commit transcript: \(error.localizedDescription, privacy: .private)")
      verifiedMemo = verifiedMemo.filter { $0.key.hash != hash }
      return nil
    }
  }

  private static func isContentHash(_ hash: String) -> Bool {
    hash.utf8.count == 64
      && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private func verify(hash: String, pair: Pair) -> Bool {
    guard
      let subtitleData = try? LocalFileAccess.readData(
        at: pair.srt, maximumBytes: SRT.maximumFileBytes, followSymlinks: false),
      let source = String(data: subtitleData, encoding: .utf8), !SRT.parse(source).isEmpty,
      let data = try? LocalFileAccess.readData(
        at: pair.manifest, maximumBytes: 64 * 1_024, followSymlinks: false),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      (object["audio_sha256"] as? String) == hash,
      let expected = object["srt_sha256"] as? String,
      expected == SHA256.hash(data: subtitleData).map({ String(format: "%02x", $0) }).joined()
    else { return false }

    let schema = (object["schema"] as? NSNumber)?.intValue
    let appleNative = schema == 2 && (object["engine"] as? String) == "apple.speechtranscriber"
    let legacyV1 =
      schema == 1
      && (object["model"] as? String) == "base.en"
      && (object["language"] as? String) == "English"
    return appleNative || legacyV1
  }

  private func signature(pair: Pair) -> Signature? {
    guard let srt = transcriptFileSignature(pair.srt),
      let manifest = transcriptFileSignature(pair.manifest)
    else {
      return nil
    }
    return Signature(
      srtSize: srt.size,
      srtMTimeNS: srt.mtimeNS,
      srtCTimeNS: srt.ctimeNS,
      manifestSize: manifest.size,
      manifestMTimeNS: manifest.mtimeNS,
      manifestCTimeNS: manifest.ctimeNS)
  }

  private func transcriptFileSignature(_ url: URL) -> (
    size: UInt64, mtimeNS: Int64, ctimeNS: Int64
  )? {
    guard LocalFileAccess.isRegularFile(url),
      let signature = fileSignature(url), signature.size >= 0
    else { return nil }
    return (UInt64(signature.size), signature.mtimeNS, signature.ctimeNS)
  }
}
