// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation
import Speech

/// Compile-only target-SDK smoke. It deliberately does not download assets or
/// transcribe user media. The selected Xcode must type-check the exact Speech/Foundation
/// surfaces used by NativeTranscriber before a candidate can be called buildable.
func cuelixaSpeechAPISmoke(audioFile: AVAudioFile) async throws {
  _ = SpeechTranscriber.isAvailable
  guard
    let locale = await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: "en-US"))
  else { return }

  let transcriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: [],
    reportingOptions: [],
    attributeOptions: [.audioTimeRange])

  _ = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])

  let analyzer = SpeechAnalyzer(modules: [transcriber])
  let resultConsumer = Task {
    for try await result in transcriber.results {
      let attributed = result.text
      _ = result.range
      _ = result.isFinal
      for run in attributed.runs {
        _ = run.range
        _ = run.audioTimeRange
        _ = String(attributed[run.range].characters)
      }
    }
  }

  if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
    try await analyzer.finalizeAndFinish(through: lastSample)
  } else {
    await analyzer.cancelAndFinishNow()
  }
  _ = try await resultConsumer.value
}
