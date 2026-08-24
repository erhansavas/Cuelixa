// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation
import Speech

protocol TranscriptionExecuting: Sendable {
  func transcribe(
    snapshot: URL, duration: Double,
    progress: @escaping @MainActor @Sendable (String, Int?) -> Void
  ) async throws -> [SubtitleCue]

  func cancelAndWait() async
}

/// Production adapter around Apple's on-device Speech APIs. Queue ownership,
/// watcher cancellation, snapshot verification and cache publication remain in
/// NativeTranscriber and can therefore be tested with a deterministic executor.
actor AppleSpeechExecutor: TranscriptionExecuting {
  private var analyzer: SpeechAnalyzer?

  func transcribe(
    snapshot: URL, duration trackDuration: Double,
    progress: @escaping @MainActor @Sendable (String, Int?) -> Void
  ) async throws -> [SubtitleCue] {
    try Task.checkCancellation()
    await progress("Checking Apple Speech assets…", nil)
    guard SpeechTranscriber.isAvailable else { throw CuelixaError.unsupportedLocale }
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: "en-US"))
    else {
      throw CuelixaError.unsupportedLocale
    }

    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange])
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      await progress("Installing local speech model…", nil)
      try await request.downloadAndInstall()
    }
    try Task.checkCancellation()

    let audioFile = try AVAudioFile(forReading: snapshot)
    let speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
    analyzer = speechAnalyzer

    async let generatedCues = Self.collectCues(
      from: transcriber, duration: trackDuration
    ) { percent in
      progress("Creating synchronized subtitles", percent)
    }

    do {
      await progress("Preparing subtitles", nil)
      if let lastSample = try await speechAnalyzer.analyzeSequence(from: audioFile) {
        try await speechAnalyzer.finalizeAndFinish(through: lastSample)
      } else {
        await speechAnalyzer.cancelAndFinishNow()
      }
      let cues = try await generatedCues
      analyzer = nil
      return cues
    } catch {
      await speechAnalyzer.cancelAndFinishNow()
      analyzer = nil
      throw error
    }
  }

  func cancelAndWait() async {
    guard let analyzer else { return }
    await analyzer.cancelAndFinishNow()
    self.analyzer = nil
  }

  /// Speech result consumption deliberately runs outside the executor actor.
  /// Only Sendable Speech values and an isolated progress callback cross into
  /// this child concurrency region.
  @concurrent
  private static func collectCues(
    from transcriber: SpeechTranscriber, duration trackDuration: Double,
    progress: @escaping @MainActor @Sendable (Int?) -> Void
  ) async throws -> [SubtitleCue] {
    var fragments: [TimedTranscriptFragment] = []
    var latestTime = 0.0
    var hasPublishedProgress = false
    var lastPublishedPercent: Int?

    for try await result in transcriber.results {
      try Task.checkCancellation()
      guard result.isFinal else { continue }
      let attributed = result.text
      let fullText = String(attributed.characters)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !fullText.isEmpty else { continue }

      var appendedTimedRun = false
      for run in attributed.runs {
        guard let timeRange = run.audioTimeRange else { continue }
        let start = CMTimeGetSeconds(timeRange.start)
        let duration = CMTimeGetSeconds(timeRange.duration)
        guard start.isFinite, duration.isFinite, start >= 0, duration > 0 else { continue }
        let text = String(attributed[run.range].characters)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        let end = start + max(0.05, duration)
        fragments.append(TimedTranscriptFragment(start: start, end: end, text: text))
        latestTime = max(latestTime, end)
        appendedTimedRun = true
      }

      if !appendedTimedRun {
        let start = max(0, CMTimeGetSeconds(result.range.start))
        let duration = max(0, CMTimeGetSeconds(result.range.duration))
        guard start.isFinite, duration.isFinite, duration > 0 else { continue }
        let end = start + max(0.25, duration)
        fragments.append(TimedTranscriptFragment(start: start, end: end, text: fullText))
        latestTime = max(latestTime, end)
      }

      let percent: Int?
      if trackDuration > 0 {
        percent = min(99, max(1, Int((latestTime / trackDuration) * 100)))
      } else {
        percent = nil
      }
      if !hasPublishedProgress || lastPublishedPercent != percent {
        hasPublishedProgress = true
        lastPublishedPercent = percent
        await progress(percent)
      }
    }

    return SubtitleSegmenter.cues(from: fragments)
  }
}
