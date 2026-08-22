// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation

private enum LocalPlaybackSmokeError: LocalizedError {
  case itemFailed(String)
  case itemTimedOut
  case playbackTimedOut(String)
  case fixtureInvalid

  var errorDescription: String? {
    switch self {
    case .itemFailed(let detail): "AVPlayerItem failed: \(detail)"
    case .itemTimedOut: "AVPlayerItem did not become readyToPlay before the smoke timeout."
    case .playbackTimedOut(let detail): "AVPlayer playback did not advance: \(detail)"
    case .fixtureInvalid: "Generated PCM/WAV fixture did not satisfy the expected media contract."
    }
  }
}

@MainActor
private final class LocalPlaybackProbe {
  private let player: AVPlayer
  private let item: AVPlayerItem
  private var itemObservation: NSKeyValueObservation?
  private var readyTimeoutTask: Task<Void, Never>?
  private var readyContinuation: CheckedContinuation<Void, Error>?
  private var boundaryObserver: Any?
  private var progressTimeoutTask: Task<Void, Never>?
  private var progressContinuation: CheckedContinuation<Void, Error>?

  init(player: AVPlayer, item: AVPlayerItem) {
    self.player = player
    self.item = item
  }

  func waitUntilReady() async throws {
    switch item.status {
    case .readyToPlay:
      return
    case .failed:
      throw LocalPlaybackSmokeError.itemFailed(item.error?.localizedDescription ?? "unknown")
    case .unknown:
      break
    @unknown default:
      throw LocalPlaybackSmokeError.itemFailed("unknown future AVPlayerItem status")
    }

    try await withCheckedThrowingContinuation { continuation in
      readyContinuation = continuation
      readyTimeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        self?.finishReady(.failure(LocalPlaybackSmokeError.itemTimedOut))
      }
      itemObservation = item.observe(\.status, options: [.initial, .new]) {
        [weak self, weak item] _, _ in
        Task { @MainActor in
          guard let self, let item else { return }
          switch item.status {
          case .readyToPlay:
            self.finishReady(.success(()))
          case .failed:
            self.finishReady(
              .failure(
                LocalPlaybackSmokeError.itemFailed(
                  item.error?.localizedDescription ?? "unknown")))
          case .unknown:
            break
          @unknown default:
            self.finishReady(
              .failure(LocalPlaybackSmokeError.itemFailed("unknown future AVPlayerItem status")))
          }
        }
      }
    }
  }

  func playAndVerifyProgress() async throws {
    let baseline = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0)
    let target = baseline + 0.15
    try await withCheckedThrowingContinuation { continuation in
      progressContinuation = continuation
      let boundary = CMTime(seconds: target, preferredTimescale: 600)
      boundaryObserver = player.addBoundaryTimeObserver(
        forTimes: [NSValue(time: boundary)], queue: .main
      ) { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          let current = self.player.currentTime().seconds
          guard self.player.timeControlStatus == .playing, current.isFinite,
            current > baseline + 0.05
          else {
            self.finishProgress(
              .failure(
                LocalPlaybackSmokeError.playbackTimedOut(
                  "boundary fired without a playing/advancing timebase")))
            return
          }
          self.finishProgress(.success(()))
        }
      }
      progressTimeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, let self else { return }
        let current = self.player.currentTime().seconds
        let reason = self.player.reasonForWaitingToPlay?.rawValue ?? "none"
        self.finishProgress(
          .failure(
            LocalPlaybackSmokeError.playbackTimedOut(
              "status=\(self.player.timeControlStatus) waiting=\(reason) current=\(current)")))
      }
      player.play()
    }
  }

  func stop() {
    readyTimeoutTask?.cancel()
    readyTimeoutTask = nil
    progressTimeoutTask?.cancel()
    progressTimeoutTask = nil
    itemObservation?.invalidate()
    itemObservation = nil
    if let boundaryObserver {
      player.removeTimeObserver(boundaryObserver)
      self.boundaryObserver = nil
    }
    player.pause()
    player.replaceCurrentItem(with: nil)
  }

  private func finishReady(_ result: Result<Void, Error>) {
    guard let continuation = readyContinuation else { return }
    readyContinuation = nil
    readyTimeoutTask?.cancel()
    readyTimeoutTask = nil
    itemObservation?.invalidate()
    itemObservation = nil
    continuation.resume(with: result)
  }

  private func finishProgress(_ result: Result<Void, Error>) {
    guard let continuation = progressContinuation else { return }
    progressContinuation = nil
    progressTimeoutTask?.cancel()
    progressTimeoutTask = nil
    if let boundaryObserver {
      player.removeTimeObserver(boundaryObserver)
      self.boundaryObserver = nil
    }
    continuation.resume(with: result)
  }
}

private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
  var littleEndian = value.littleEndian
  Swift.withUnsafeBytes(of: &littleEndian) { bytes in
    data.append(contentsOf: bytes)
  }
}

private func generatedPCMFixture() throws -> URL {
  let sampleRate: UInt32 = 44_100
  let channels: UInt16 = 1
  let bitsPerSample: UInt16 = 16
  let durationSeconds: UInt32 = 2
  let frameCount = sampleRate * durationSeconds
  let bytesPerSample = UInt32(bitsPerSample / 8)
  let dataByteCount = frameCount * UInt32(channels) * bytesPerSample
  let byteRate = sampleRate * UInt32(channels) * bytesPerSample
  let blockAlign = channels * (bitsPerSample / 8)

  var wav = Data()
  wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46])  // RIFF
  appendLittleEndian(UInt32(36) + dataByteCount, to: &wav)
  wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45])  // WAVE
  wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])  // fmt
  appendLittleEndian(UInt32(16), to: &wav)
  appendLittleEndian(UInt16(1), to: &wav)  // linear PCM
  appendLittleEndian(channels, to: &wav)
  appendLittleEndian(sampleRate, to: &wav)
  appendLittleEndian(byteRate, to: &wav)
  appendLittleEndian(blockAlign, to: &wav)
  appendLittleEndian(bitsPerSample, to: &wav)
  wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61])  // data
  appendLittleEndian(dataByteCount, to: &wav)
  wav.append(Data(count: Int(dataByteCount)))

  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("cuelixa-local-playback-smoke-\(UUID().uuidString)")
    .appendingPathExtension("wav")
  try wav.write(to: url, options: .atomic)
  return url
}

@main
struct LocalPlaybackSmoke {
  @MainActor
  static func main() async throws {
    let fixture = try generatedPCMFixture()
    defer { try? FileManager.default.removeItem(at: fixture) }

    let asset = AVURLAsset(url: fixture)
    let isPlayable = try await asset.load(.isPlayable)
    let duration = try await asset.load(.duration)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let durationSeconds = duration.seconds
    guard isPlayable, durationSeconds.isFinite, durationSeconds > 1,
      !audioTracks.isEmpty
    else {
      throw LocalPlaybackSmokeError.fixtureInvalid
    }

    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    let probe = LocalPlaybackProbe(player: player, item: item)
    try await probe.waitUntilReady()
    try await probe.playAndVerifyProgress()
    let advancedTime = player.currentTime().seconds
    probe.stop()

    print("LOCAL_AVASSET_ASYNC_LOAD=PASS")
    print("LOCAL_AVPLAYERITEM_READY=PASS")
    print("LOCAL_AVPLAYER_PLAYING_AND_TIME_ADVANCE=PASS current=\(advancedTime)")
    print("LOCAL_AVPLAYER_TEARDOWN=PASS")
  }
}
