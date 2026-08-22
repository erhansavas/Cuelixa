// SPDX-License-Identifier: Apache-2.0
import Foundation

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

// SAFETY: the only shared mutable state is verifiedMemo, and every access is
// serialized by memoLock. URLs/signatures stored in the memo are immutable values.
final class TranscriptCache: @unchecked Sendable {
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

  private let memoLock = NSLock()
  private var verifiedMemo: [MemoKey: (Signature, URL?)] = [:]

  /// Preferred durable transcript URL. Call verifiedSRTURL when opening an
  /// existing transcript because r20/r21 cache-resident output is still supported.
  func srtURL(hash: String) -> URL {
    AppPaths.transcripts.appendingPathComponent(hash + ".srt")
  }

  func manifestURL(hash: String) -> URL {
    AppPaths.transcripts.appendingPathComponent(hash + ".json")
  }

  private func legacySRTURL(hash: String) -> URL {
    AppPaths.legacySubtitles.appendingPathComponent(hash + ".srt")
  }

  private func legacyManifestURL(hash: String) -> URL {
    AppPaths.legacySubtitles.appendingPathComponent(hash + ".json")
  }

  func verified(hash: String) -> Bool { verifiedSRTURL(hash: hash) != nil }

  /// Returns the exact verified SRT that should be played. Durable output
  /// wins; a valid r20/r21 cache pair remains readable non-destructively.
  func verifiedSRTURL(hash: String) -> URL? {
    let candidates = [
      Pair(srt: srtURL(hash: hash), manifest: manifestURL(hash: hash)),
      Pair(srt: legacySRTURL(hash: hash), manifest: legacyManifestURL(hash: hash)),
    ]

    for pair in candidates {
      guard let signature = signature(pair: pair) else { continue }
      let key = MemoKey(hash: hash, sourcePath: pair.srt.path)
      memoLock.lock()
      if let memo = verifiedMemo[key], memo.0 == signature {
        let cached = memo.1
        memoLock.unlock()
        if let cached { return cached }
        continue
      }
      memoLock.unlock()

      let result = verify(hash: hash, pair: pair) ? pair.srt : nil
      memoLock.lock()
      verifiedMemo[key] = (signature, result)
      memoLock.unlock()
      if let result { return result }
    }

    return nil
  }

  func pruneVerificationMemo(keeping hashes: Set<String>) {
    memoLock.lock()
    verifiedMemo = verifiedMemo.filter { hashes.contains($0.key.hash) }
    memoLock.unlock()
  }

  /// Deletes only subtitle artifacts owned by Cuelixa. User-owned sidecar SRT
  /// files beside lesson audio are intentionally outside these directories and
  /// are never touched by this maintenance action.
  func resetManagedTranscripts() throws {
    let fm = FileManager.default
    for directory in [AppPaths.transcripts, AppPaths.legacySubtitles] {
      guard fm.fileExists(atPath: directory.path) else { continue }
      for item in try fm.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
      ) {
        try fm.removeItem(at: item)
      }
    }

    memoLock.lock()
    verifiedMemo.removeAll(keepingCapacity: false)
    memoLock.unlock()
  }

  /// Publishes newly generated transcripts to durable Application Support.
  /// The SRT is committed before the manifest; verification requires both files
  /// and matching hashes, so an interrupted write can never look valid.
  func commit(hash: String, cues: [SubtitleCue]) -> URL? {
    try? AppPaths.ensure()
    guard !cues.isEmpty else { return nil }
    let dest = srtURL(hash: hash)
    let manifestDest = manifestURL(hash: hash)
    let stage = AppPaths.staging.appendingPathComponent(UUID().uuidString + ".srt")
    defer { try? FileManager.default.removeItem(at: stage) }

    do {
      guard let encoded = SRT.encode(cues).data(using: .utf8) else { return nil }
      try encoded.write(to: stage, options: .atomic)
      guard SRT.validate(url: stage) else { return nil }

      if FileManager.default.fileExists(atPath: dest.path) {
        _ = try FileManager.default.replaceItemAt(dest, withItemAt: stage)
      } else {
        try FileManager.default.moveItem(at: stage, to: dest)
      }
      guard let subtitleHash = sha256File(dest) else { return nil }

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
      try data.write(to: manifestDest, options: .atomic)

      memoLock.lock()
      verifiedMemo = verifiedMemo.filter { $0.key.hash != hash }
      memoLock.unlock()
      return verifiedSRTURL(hash: hash)
    } catch {
      memoLock.lock()
      verifiedMemo = verifiedMemo.filter { $0.key.hash != hash }
      memoLock.unlock()
      return nil
    }
  }

  private func verify(hash: String, pair: Pair) -> Bool {
    guard SRT.validate(url: pair.srt),
      let data = try? Data(contentsOf: pair.manifest),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      (object["audio_sha256"] as? String) == hash,
      let expected = object["srt_sha256"] as? String,
      let actual = sha256File(pair.srt), expected == actual
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
    guard let signature = fileSignature(url), signature.size >= 0 else { return nil }
    return (UInt64(signature.size), signature.mtimeNS, signature.ctimeNS)
  }
}
