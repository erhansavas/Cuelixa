// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Combine
import Foundation
import MediaPlayer
import OSLog

enum PlaybackState: String, Equatable {
  case idle
  case preparing
  case ready
  case playing
  case paused
  case seeking
  case failed
  case stopped
}

@MainActor
final class PlaybackController: ObservableObject {
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "Playback")
  private let directories: AppDirectories
  @Published private(set) var state: PlaybackState = .idle
  @Published private(set) var position: Double = 0
  @Published private(set) var duration: Double = 0
  @Published private(set) var subtitleText = ""
  @Published var volume: Double = 0.35 {
    didSet {
      player?.volume = Float(max(0, min(1, volume)))
      saveVolume()
    }
  }

  var isPreparing: Bool { state == .preparing }
  var isPlaying: Bool { state == .playing }
  var isPlaybackRequested: Bool { wantsPlayback }
  var isRunning: Bool {
    switch state {
    case .ready, .playing, .paused, .seeking:
      true
    case .idle, .preparing, .failed, .stopped:
      false
    }
  }

  private(set) var activeHash: String?
  @Published private(set) var activeTitle = ""
  private var player: AVPlayer?
  private var observer: Any?
  private var endObserver: NSObjectProtocol?
  private var failureObserver: NSObjectProtocol?
  private var itemStatusObservation: NSKeyValueObservation?
  private var playerStatusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var cues: [SubtitleCue] = []
  private var cuePrefixMaximumEnds: [Double] = []
  private var currentCueIndex: Int?
  private var lastConfirmedPosition: Double = 0
  private var lastSaved = Date.distantPast
  private var scrubbing = false
  private var scrubValue: Double = 0
  private var seekTarget: Double?
  private var exactSeekTask: Task<Void, Never>?
  private var seekTimeoutTask: Task<Void, Never>?
  private var seekGeneration: UInt64 = 0
  private var playbackGeneration: UInt64 = 0
  private var wantsPlayback = false
  private var scrubWasPlaying = false
  private var playbackHasStarted = false
  private var assetPreparationTask: Task<Void, Never>?
  private var assetPreparationWatchdogTask: Task<Void, Never>?
  private var itemPreparationWatchdogTask: Task<Void, Never>?
  private var playbackStartWatchdogTask: Task<Void, Never>?
  private var startProgressObserver: Any?
  private var startBaselineTime: Double?
  private var startRequiredDelta: Double = 0
  private var startObservedPlaying = false
  private var startObservedProgress = false
  private var activeFileName = ""
  private var activeFileExtension = ""
  private var activeFileSize: UInt64 = 0
  private var lastNowPlayingTimeUpdate = Date.distantPast
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
  var onPositionSave: ((String, Double) -> Void)?
  var onEnded: ((String) -> Void)?
  var onPlaybackStarted: (() -> Void)?
  var onPlaybackFailed: ((String) -> Void)?
  var onSubtitleChanged: ((String) -> Void)?
  var onActivity: (() -> Void)?
  var onStateChanged: (() -> Void)?
  var onPresentationChanged: (() -> Void)?

  init(directories: AppDirectories = AppPaths.current) {
    self.directories = directories
    if let d = try? LocalFileAccess.readData(
      at: directories.preferences, maximumBytes: 64 * 1_024, followSymlinks: false),
      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
      let v = o["volume"] as? Double
    {
      volume = max(0, min(1, v))
    }
  }

  @discardableResult
  func start(track: Track, subtitleURL: URL?) -> Bool {
    let resumePosition = activeHash == track.contentHash ? position : track.position
    stop(save: isRunning || isPreparing)
    playbackGeneration &+= 1
    let generation = playbackGeneration

    let parsedCues = subtitleURL.map(SRT.parse(url:)) ?? []
    if subtitleURL != nil, parsedCues.isEmpty {
      setState(.failed)
      onPlaybackFailed?(
        "Prepared subtitles could not be read. Re-prepare subtitles for this lesson and try again.")
      return false
    }

    activeHash = track.contentHash
    activeTitle = track.title
    position = track.completed ? 0 : max(0, resumePosition)
    lastConfirmedPosition = position
    lastSaved = .distantPast
    duration = max(0, track.duration)
    wantsPlayback = true
    playbackHasStarted = false
    cues = parsedCues
    cuePrefixMaximumEnds = SubtitleTimeline.prefixMaximumEnds(for: cues)
    currentCueIndex = nil
    subtitleText = ""
    updateSubtitle(at: position)
    setState(.preparing)

    let fileURL = URL(fileURLWithPath: track.path).standardizedFileURL.resolvingSymlinksInPath()
    do {
      activeFileSize = try localFileInfo(for: fileURL)
      activeFileName = fileURL.deletingPathExtension().lastPathComponent
      activeFileExtension = fileURL.pathExtension.lowercased()
      logSession(
        generation,
        "file-preflight regular=true readable=true ext=\(activeFileExtension) size=\(activeFileSize)"
      )
    } catch {
      failPlayback(error, context: "file-preflight")
      return false
    }

    beginAssetPreparation(
      fileURL: fileURL, requestedResumePosition: position, generation: generation)
    return true
  }

  private func localFileInfo(for url: URL) throws -> UInt64 {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw CuelixaPlaybackError.missingOrNonRegularFile
    }
    guard fileManager.isReadableFile(atPath: url.path) else {
      throw CuelixaPlaybackError.unreadableFile
    }
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw CuelixaPlaybackError.missingOrNonRegularFile
    }
    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    guard size > 0 else { throw CuelixaPlaybackError.emptyFile }
    return size
  }

  private func beginAssetPreparation(
    fileURL: URL, requestedResumePosition: Double, generation: UInt64
  ) {
    assetPreparationWatchdogTask?.cancel()
    assetPreparationWatchdogTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self, self.playbackGeneration == generation,
        self.state == .preparing, self.player == nil
      else { return }
      self.logPlaybackSnapshot(generation, context: "asset-preparation-timeout")
      self.failPlayback(
        CuelixaPlaybackError.assetPreparationTimedOut, context: "asset-preparation-timeout")
    }

    assetPreparationTask?.cancel()
    assetPreparationTask = Task { [weak self] in
      guard let self else { return }
      let asset = AVURLAsset(url: fileURL)
      do {
        let isPlayable = try await asset.load(.isPlayable)
        try Task.checkCancellation()
        let loadedDuration = try await asset.load(.duration)
        try Task.checkCancellation()
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        try Task.checkCancellation()
        guard self.playbackGeneration == generation, self.state == .preparing else { return }

        let loadedDurationSeconds = CMTimeGetSeconds(loadedDuration)
        self.logSession(
          generation,
          "asset-loaded playable=\(isPlayable) duration=\(self.loggableTime(loadedDurationSeconds)) audioTracks=\(audioTracks.count)"
        )

        guard isPlayable else {
          throw CuelixaPlaybackError.assetNotPlayable
        }
        guard loadedDurationSeconds.isFinite, loadedDurationSeconds > 0 else {
          throw CuelixaPlaybackError.invalidDuration
        }
        guard !audioTracks.isEmpty else {
          throw CuelixaPlaybackError.noAudioTrack
        }

        self.assetPreparationWatchdogTask?.cancel()
        self.assetPreparationWatchdogTask = nil
        self.assetPreparationTask = nil
        self.finishAssetPreparation(
          asset: asset, duration: loadedDurationSeconds,
          requestedResumePosition: requestedResumePosition, generation: generation)
      } catch is CancellationError {
        return
      } catch {
        guard self.playbackGeneration == generation, self.state == .preparing else { return }
        self.assetPreparationWatchdogTask?.cancel()
        self.assetPreparationWatchdogTask = nil
        self.assetPreparationTask = nil
        self.failPlayback(error, context: "asset-preparation")
      }
    }
  }

  private func finishAssetPreparation(
    asset: AVURLAsset, duration loadedDuration: Double,
    requestedResumePosition: Double, generation: UInt64
  ) {
    guard playbackGeneration == generation, state == .preparing, player == nil else { return }

    duration = loadedDuration
    position = PlaybackResumePolicy.normalizedPosition(
      requestedResumePosition, duration: loadedDuration)
    lastConfirmedPosition = position
    updateSubtitle(at: position)
    logSession(
      generation,
      "resume requested=\(loggableTime(requestedResumePosition)) effective=\(loggableTime(position)) duration=\(loggableTime(duration))"
    )

    let item = AVPlayerItem(asset: asset)
    let newPlayer = AVPlayer(playerItem: item)
    player = newPlayer
    newPlayer.volume = Float(volume)
    installPlayerObservers(item: item, player: newPlayer, generation: generation)
    startItemPreparationWatchdog(item: item, player: newPlayer, generation: generation)
    logPlaybackSnapshot(generation, context: "player-created")
  }

  private func installPlayerObservers(item: AVPlayerItem, player: AVPlayer, generation: UInt64) {
    endObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
    ) { [weak self, weak item] _ in
      Task { @MainActor in
        guard let self, let item, self.playbackGeneration == generation,
          self.player?.currentItem === item
        else { return }
        self.logPlaybackSnapshot(generation, context: "item-ended")
        self.ended()
      }
    }

    failureObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
    ) { [weak self, weak item] notification in
      let failure = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
      Task { @MainActor in
        guard let self, let item, self.playbackGeneration == generation,
          self.player?.currentItem === item
        else { return }
        self.failPlayback(failure, context: "AVPlayerItemFailedToPlayToEndTime")
      }
    }

    itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
      [weak self, weak item] _, _ in
      Task { @MainActor in
        guard let self, let item, self.playbackGeneration == generation,
          let currentPlayer = self.player, currentPlayer.currentItem === item
        else { return }
        self.handleItemStatus(item, player: currentPlayer, generation: generation)
      }
    }

    playerStatusObservation = player.observe(\.status, options: [.initial, .new]) {
      [weak self, weak player] _, _ in
      Task { @MainActor in
        guard let self, let player, self.playbackGeneration == generation,
          self.player === player
        else { return }
        self.logPlaybackSnapshot(generation, context: "player-status")
        if player.status == .failed {
          self.failPlayback(player.error, context: "AVPlayer.status")
        }
      }
    }

    timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
      [weak self, weak player] _, _ in
      Task { @MainActor in
        guard let self, let player, self.playbackGeneration == generation,
          self.player === player
        else { return }
        self.synchronizeTimeControlState(player, generation: generation)
      }
    }
  }

  private func startItemPreparationWatchdog(
    item: AVPlayerItem, player: AVPlayer, generation: UInt64
  ) {
    itemPreparationWatchdogTask?.cancel()
    itemPreparationWatchdogTask = Task { [weak self, weak item, weak player] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self, let item, let player,
        self.playbackGeneration == generation, self.player === player,
        player.currentItem === item, item.status == .unknown
      else { return }
      self.logPlaybackSnapshot(generation, context: "item-ready-timeout")
      self.failPlayback(
        CuelixaPlaybackError.itemPreparationTimedOut, context: "item-ready-timeout")
    }
  }

  private func handleItemStatus(_ item: AVPlayerItem, player: AVPlayer, generation: UInt64) {
    guard playbackGeneration == generation, self.player === player,
      player.currentItem === item
    else { return }

    logPlaybackSnapshot(generation, context: "item-status")
    switch item.status {
    case .unknown:
      break
    case .readyToPlay:
      guard state == .preparing else { return }
      itemPreparationWatchdogTask?.cancel()
      itemPreparationWatchdogTask = nil
      setState(.ready)
      if position > 0.05 {
        setState(.seeking)
        logSession(generation, "initial-seek requested=\(loggableTime(position))")
        exactSeek(to: position)
      } else {
        requestVerifiedPlaybackStart(player, generation: generation)
      }
    case .failed:
      failPlayback(item.error, context: "AVPlayerItem.status")
    @unknown default:
      failPlayback(nil, context: "AVPlayerItem.status.unknown")
    }
  }

  private func requestVerifiedPlaybackStart(_ player: AVPlayer, generation: UInt64) {
    guard playbackGeneration == generation, self.player === player,
      player.currentItem?.status == .readyToPlay, wantsPlayback
    else { return }

    removeStartProgressObserver()
    playbackStartWatchdogTask?.cancel()
    playbackStartWatchdogTask = nil
    startObservedPlaying = false
    startObservedProgress = false

    let baseline = finiteTime(player.currentTime().seconds, fallback: position)
    let remaining = max(0, duration - baseline)
    let delta = min(0.20, max(0.05, remaining * 0.05))
    startBaselineTime = baseline
    startRequiredDelta = delta

    let boundarySeconds = min(max(0, duration - 0.01), baseline + delta)
    if boundarySeconds > baseline + 0.001 {
      let boundary = CMTime(seconds: boundarySeconds, preferredTimescale: 600)
      startProgressObserver = player.addBoundaryTimeObserver(
        forTimes: [NSValue(time: boundary)], queue: .main
      ) { [weak self, weak player] in
        Task { @MainActor in
          guard let self, let player, self.playbackGeneration == generation,
            self.player === player, !self.playbackHasStarted
          else { return }
          let current = self.finiteTime(player.currentTime().seconds, fallback: self.position)
          let baseline = self.startBaselineTime ?? current
          if current - baseline >= max(0.02, self.startRequiredDelta * 0.5) {
            self.startObservedProgress = true
            self.logSession(
              generation,
              "start-progress baseline=\(self.loggableTime(baseline)) current=\(self.loggableTime(current)) advanced=true"
            )
            self.confirmPlaybackStartIfProven(player, generation: generation)
          }
        }
      }
    }

    playbackStartWatchdogTask = Task { [weak self, weak player] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled, let self, let player,
        self.playbackGeneration == generation, self.player === player,
        !self.playbackHasStarted, self.wantsPlayback
      else { return }

      let current = self.finiteTime(player.currentTime().seconds, fallback: self.position)
      let baseline = self.startBaselineTime ?? current
      let advanced = current - baseline >= max(0.02, self.startRequiredDelta * 0.5)
      if player.timeControlStatus == .playing, advanced {
        self.startObservedPlaying = true
        self.startObservedProgress = true
        self.logSession(
          generation,
          "start-watchdog recovered baseline=\(self.loggableTime(baseline)) current=\(self.loggableTime(current))"
        )
        self.confirmPlaybackStartIfProven(player, generation: generation)
        return
      }

      self.logPlaybackSnapshot(generation, context: "playback-start-timeout")
      self.failPlayback(
        CuelixaPlaybackError.playbackStartTimedOut(
          reason: self.waitingReasonDescription(player.reasonForWaitingToPlay)),
        context: "playback-start-timeout")
    }

    logPlaybackSnapshot(generation, context: "play-request")
    player.play()
    synchronizeTimeControlState(player, generation: generation)
  }

  private func confirmPlaybackStartIfProven(_ player: AVPlayer, generation: UInt64) {
    guard playbackGeneration == generation, self.player === player, wantsPlayback,
      !playbackHasStarted, startObservedPlaying, startObservedProgress
    else { return }

    playbackHasStarted = true
    playbackStartWatchdogTask?.cancel()
    playbackStartWatchdogTask = nil
    removeStartProgressObserver()
    installPeriodicObserver(on: player)
    installRemoteCommands()
    setState(.playing)
    let current = finiteTime(player.currentTime().seconds, fallback: position)
    position = current
    lastConfirmedPosition = current
    updateSubtitle(at: current)
    logSession(
      generation,
      "playback-confirmed current=\(loggableTime(current)) timeControl=playing advanced=true"
    )
    refreshNowPlaying()
    onPlaybackStarted?()
  }

  private func installPeriodicObserver(on player: AVPlayer) {
    guard observer == nil else { return }
    // 10 Hz is sufficient for a spoken-audio transport and subtitle overlay.
    // Exact user seeks remain event-driven; readiness is established first so a
    // failed item never creates a recurring time observer.
    let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
    observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      Task { @MainActor in self?.sample(CMTimeGetSeconds(time)) }
    }
  }

  private func synchronizeTimeControlState(_ player: AVPlayer, generation: UInt64? = nil) {
    guard self.player === player else { return }
    if let generation, playbackGeneration != generation { return }

    let activeGeneration = playbackGeneration
    logPlaybackSnapshot(activeGeneration, context: "time-control")

    if !playbackHasStarted {
      if wantsPlayback, player.timeControlStatus == .playing {
        startObservedPlaying = true
        confirmPlaybackStartIfProven(player, generation: activeGeneration)
      }
      return
    }

    if !scrubbing, seekTarget == nil, state != .preparing, state != .failed, state != .stopped {
      switch player.timeControlStatus {
      case .playing:
        if wantsPlayback { setState(.playing) }
      case .paused:
        if !wantsPlayback { setState(.paused) }
      case .waitingToPlayAtSpecifiedRate:
        if wantsPlayback { setState(.ready) }
      @unknown default:
        break
      }
    }
    refreshNowPlaying()
  }

  private func setState(_ newState: PlaybackState) {
    guard state != newState else { return }
    state = newState
    onStateChanged?()
    onPresentationChanged?()
  }

  private func sample(_ value: Double) {
    guard isRunning, value.isFinite else { return }
    if scrubbing {
      updateSubtitle(at: scrubValue)
      return
    }
    if seekTarget != nil {
      return
    }
    if let actualDuration = player?.currentItem?.duration.seconds,
      actualDuration.isFinite, actualDuration > 0,
      abs(actualDuration - duration) > 0.01
    {
      duration = actualDuration
    }
    position = max(0, min(value, duration > 0 ? duration : value))
    lastConfirmedPosition = position
    updateSubtitle(at: position)
    if let h = activeHash, Date().timeIntervalSince(lastSaved) >= 10 {
      lastSaved = Date()
      onPositionSave?(h, position)
    }
    refreshNowPlayingTime()
    onPresentationChanged?()
  }
  private func updateSubtitle(at t: Double) {
    let resolvedIndex = cueIndex(at: t)
    guard resolvedIndex != currentCueIndex else { return }
    currentCueIndex = resolvedIndex
    let text = resolvedIndex.map { cues[$0].text } ?? ""
    let balanced = SubtitleBalancer.balance(text, maxLineChars: 58, maxLines: 3)
    if balanced != subtitleText {
      subtitleText = balanced
      onSubtitleChanged?(balanced)
    }
  }

  /// Uses the same timing semantics exercised by SubtitleSmoke so runtime
  /// playback cannot disagree with parser/timeline tests at cue boundaries.
  private func cueIndex(at time: Double) -> Int? {
    SubtitleTimeline.activeCueIndex(in: cues, prefixMaximumEnds: cuePrefixMaximumEnds, at: time)
  }

  func togglePlayPause() {
    guard let player, isRunning else { return }
    onActivity?()
    if wantsPlayback {
      wantsPlayback = false
      player.pause()
      if !playbackHasStarted { cancelPlaybackStartVerification() }
      setState(.paused)
      persistCurrentPosition()
    } else {
      wantsPlayback = true
      if seekTarget == nil {
        if playbackHasStarted {
          player.play()
          synchronizeTimeControlState(player)
        } else {
          requestVerifiedPlaybackStart(player, generation: playbackGeneration)
        }
      }
    }
    refreshNowPlaying()
  }

  func pause() {
    guard let player, isRunning else { return }
    onActivity?()
    wantsPlayback = false
    player.pause()
    if !playbackHasStarted { cancelPlaybackStartVerification() }
    setState(.paused)
    persistCurrentPosition()
    refreshNowPlaying()
  }

  func play() {
    guard let player, isRunning else { return }
    onActivity?()
    wantsPlayback = true
    guard seekTarget == nil else { return }
    if playbackHasStarted {
      player.play()
      synchronizeTimeControlState(player)
    } else {
      requestVerifiedPlaybackStart(player, generation: playbackGeneration)
    }
  }

  func seekRelative(_ delta: Double) {
    commitSeek(to: max(0, min(duration, position + delta)))
  }

  func beginScrub(_ value: Double) {
    guard let player, isRunning else { return }
    onActivity?()
    scrubbing = true
    scrubValue = max(0, min(duration, value))
    position = scrubValue
    seekGeneration &+= 1
    exactSeekTask?.cancel()
    exactSeekTask = nil
    seekTarget = nil
    seekTimeoutTask?.cancel()
    seekTimeoutTask = nil
    player.currentItem?.cancelPendingSeeks()

    // Audio-only scrubbing doesn't need decoder preview seeks. Pause once, let
    // the slider/subtitle timeline follow the pointer in memory, then issue one
    // exact AVPlayer seek when the gesture commits. This avoids a seek storm and
    // keeps the fanless-Mac path substantially quieter.
    scrubWasPlaying = wantsPlayback && isPlaying
    if scrubWasPlaying { player.pause() }
    setState(.seeking)
    refreshNowPlaying()
    updateSubtitle(at: scrubValue)
  }

  func liveScrub(_ value: Double) {
    guard scrubbing else { return }
    let v = max(0, min(duration, value))
    scrubValue = v
    position = v
    updateSubtitle(at: v)
    onPresentationChanged?()
  }

  func endScrub(_ value: Double) {
    guard scrubbing else { return }
    let v = max(0, min(duration, value))
    scrubValue = v
    position = v
    scrubbing = false
    updateSubtitle(at: v)
    exactSeek(to: v, persistOnSuccess: true)
    scrubWasPlaying = false
    refreshNowPlayingTime(force: true)
  }

  private func commitSeek(to value: Double) {
    guard isRunning else { return }
    onActivity?()
    let v = max(0, min(duration, value))
    position = v
    updateSubtitle(at: v)
    setState(.seeking)
    exactSeek(to: v, persistOnSuccess: true)
    refreshNowPlayingTime(force: true)
  }

  func exactSeek(to seconds: Double, persistOnSuccess: Bool = false) {
    guard let p = player else { return }
    let target = max(0, seconds)
    p.currentItem?.cancelPendingSeeks()
    seekGeneration &+= 1
    let generation = seekGeneration
    seekTarget = target
    setState(.seeking)

    seekTimeoutTask?.cancel()
    seekTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled, let self, self.player === p,
        self.seekGeneration == generation, self.seekTarget != nil
      else { return }
      self.failPlayback(CuelixaPlaybackError.seekTimedOut, context: "seek-timeout")
    }

    let t = CMTime(seconds: target, preferredTimescale: 600)
    exactSeekTask?.cancel()
    exactSeekTask = Task { [weak self, weak p] in
      guard let self, let p else { return }
      let succeeded = await p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
      guard !Task.isCancelled, self.player === p, self.seekGeneration == generation else { return }
      self.exactSeekTask = nil
      self.seekTimeoutTask?.cancel()
      self.seekTimeoutTask = nil
      self.seekTarget = nil

      if succeeded {
        self.position = target
        self.lastConfirmedPosition = target
        self.updateSubtitle(at: target)
        if persistOnSuccess, let hash = self.activeHash {
          self.onPositionSave?(hash, target)
        }
        self.logSession(
          self.playbackGeneration,
          "seek-finished target=\(self.loggableTime(target)) success=true"
        )
        if self.wantsPlayback {
          self.setState(.ready)
          if self.playbackHasStarted {
            p.play()
            self.synchronizeTimeControlState(p)
          } else {
            self.requestVerifiedPlaybackStart(p, generation: self.playbackGeneration)
          }
        } else {
          self.setState(.paused)
          self.refreshNowPlaying()
        }
      } else {
        self.failPlayback(CuelixaPlaybackError.seekFailed, context: "seek")
      }
    }
  }

  private func ended() {
    guard let h = activeHash else { return }
    position = duration
    onPositionSave?(h, max(0, duration - 2))
    stop(save: false)
    onEnded?(h)
  }

  func stop(save: Bool = true) {
    if save, let h = activeHash { onPositionSave?(h, lastConfirmedPosition) }
    teardownPlayer()
    setState(.stopped)
  }

  private func teardownPlayer() {
    assetPreparationTask?.cancel()
    assetPreparationTask = nil
    assetPreparationWatchdogTask?.cancel()
    assetPreparationWatchdogTask = nil
    itemPreparationWatchdogTask?.cancel()
    itemPreparationWatchdogTask = nil
    playbackStartWatchdogTask?.cancel()
    playbackStartWatchdogTask = nil
    removeStartProgressObserver()
    if let observer, let player { player.removeTimeObserver(observer) }
    observer = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    failureObserver = nil
    itemStatusObservation?.invalidate()
    itemStatusObservation = nil
    playerStatusObservation?.invalidate()
    playerStatusObservation = nil
    timeControlObservation?.invalidate()
    timeControlObservation = nil
    player?.pause()
    player = nil
    playbackGeneration &+= 1
    seekGeneration &+= 1
    exactSeekTask?.cancel()
    exactSeekTask = nil
    seekTarget = nil
    seekTimeoutTask?.cancel()
    seekTimeoutTask = nil
    scrubbing = false
    wantsPlayback = false
    scrubWasPlaying = false
    playbackHasStarted = false
    startBaselineTime = nil
    startRequiredDelta = 0
    startObservedPlaying = false
    startObservedProgress = false
    activeHash = nil
    activeTitle = ""
    activeFileName = ""
    activeFileExtension = ""
    activeFileSize = 0
    cuePrefixMaximumEnds = []
    currentCueIndex = nil
    if !subtitleText.isEmpty {
      subtitleText = ""
      onSubtitleChanged?("")
    }
    clearNowPlaying()
    uninstallRemoteCommands()
  }

  private func failPlayback(_ error: Error?, context: String) {
    guard player != nil || isPreparing || isRunning else { return }
    let detail = error?.localizedDescription ?? "The lesson could not be decoded by AVFoundation."
    logPlaybackFailure(error, context: context, detail: detail)
    if let h = activeHash { onPositionSave?(h, lastConfirmedPosition) }
    teardownPlayer()
    setState(.failed)
    onPlaybackFailed?(detail)
  }

  private func logPlaybackFailure(_ error: Error?, context: String, detail: String) {
    // OSLog interpolation is evaluated through an autoclosure. Snapshot actor-owned
    // properties into local values first so Swift 6 does not require an implicit
    // `self` capture inside the logging autoclosure. This also keeps one coherent
    // file identity if teardown follows immediately after this call.
    let generation = playbackGeneration
    let fileName = activeFileName
    let fileExtension = activeFileExtension
    if let error {
      let nsError = error as NSError
      logger.error(
        "session=\(generation) context=\(context, privacy: .public) file=\(fileName, privacy: .private(mask: .hash)) ext=\(fileExtension, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) detail=\(detail, privacy: .private)"
      )
    } else {
      logger.error(
        "session=\(generation) context=\(context, privacy: .public) file=\(fileName, privacy: .private(mask: .hash)) ext=\(fileExtension, privacy: .public) detail=\(detail, privacy: .private)"
      )
    }
  }

  private func cancelPlaybackStartVerification() {
    playbackStartWatchdogTask?.cancel()
    playbackStartWatchdogTask = nil
    removeStartProgressObserver()
    startBaselineTime = nil
    startRequiredDelta = 0
    startObservedPlaying = false
    startObservedProgress = false
  }

  private func removeStartProgressObserver() {
    if let startProgressObserver, let player {
      player.removeTimeObserver(startProgressObserver)
    }
    startProgressObserver = nil
  }

  private func finiteTime(_ value: Double, fallback: Double) -> Double {
    value.isFinite && value >= 0 ? value : max(0, fallback)
  }

  private func loggableTime(_ value: Double) -> String {
    guard value.isFinite else { return "nonfinite" }
    return String(format: "%.3f", value)
  }

  private func itemStatusDescription(_ status: AVPlayerItem.Status?) -> String {
    guard let status else { return "none" }
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "unknown-future"
    }
  }

  private func playerStatusDescription(_ status: AVPlayer.Status?) -> String {
    guard let status else { return "none" }
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "unknown-future"
    }
  }

  private func timeControlDescription(_ status: AVPlayer.TimeControlStatus?) -> String {
    guard let status else { return "none" }
    switch status {
    case .paused: return "paused"
    case .waitingToPlayAtSpecifiedRate: return "waiting"
    case .playing: return "playing"
    @unknown default: return "unknown-future"
    }
  }

  private func waitingReasonDescription(_ reason: AVPlayer.WaitingReason?) -> String {
    reason?.rawValue ?? "none"
  }

  private func logSession(_ generation: UInt64, _ message: String) {
    let fileName = activeFileName
    let fileExtension = activeFileExtension
    let fileSize = activeFileSize
    logger.info(
      "session=\(generation) file=\(fileName, privacy: .private(mask: .hash)) ext=\(fileExtension, privacy: .public) size=\(fileSize) \(message, privacy: .public)"
    )
  }

  private func logPlaybackSnapshot(_ generation: UInt64, context: String) {
    let currentPlayer = player
    let currentItem = currentPlayer?.currentItem
    let current = finiteTime(currentPlayer?.currentTime().seconds ?? position, fallback: position)
    let itemStatus = itemStatusDescription(currentItem?.status)
    let playerStatus = playerStatusDescription(currentPlayer?.status)
    let timeControl = timeControlDescription(currentPlayer?.timeControlStatus)
    let waiting = waitingReasonDescription(currentPlayer?.reasonForWaitingToPlay)
    logSession(
      generation,
      "context=\(context) state=\(state.rawValue) itemStatus=\(itemStatus) playerStatus=\(playerStatus) timeControl=\(timeControl) waiting=\(waiting) requestedPlayback=\(wantsPlayback) current=\(loggableTime(current))"
    )
    if let itemError = currentItem?.error {
      let nsError = itemError as NSError
      logger.error(
        "session=\(generation) context=\(context, privacy: .public) AVPlayerItem.error domain=\(nsError.domain, privacy: .public) code=\(nsError.code) detail=\(nsError.localizedDescription, privacy: .private)"
      )
    }
    if let playerError = currentPlayer?.error {
      let nsError = playerError as NSError
      logger.error(
        "session=\(generation) context=\(context, privacy: .public) AVPlayer.error domain=\(nsError.domain, privacy: .public) code=\(nsError.code) detail=\(nsError.localizedDescription, privacy: .private)"
      )
    }
  }

  private func persistCurrentPosition() {
    guard let hash = activeHash else { return }
    lastSaved = Date()
    onPositionSave?(hash, lastConfirmedPosition)
  }

  private func saveVolume() {
    do {
      try directories.ensure()
    } catch {
      logger.error(
        "Could not prepare preferences directory: \(error.localizedDescription, privacy: .private)")
      return
    }
    var o: [String: Any] = [:]
    if let d = try? LocalFileAccess.readData(
      at: directories.preferences, maximumBytes: 64 * 1_024, followSymlinks: false),
      let old = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    {
      o = old
    }
    o["volume"] = volume
    if let d = try? JSONSerialization.data(
      withJSONObject: o, options: [.prettyPrinted, .sortedKeys])
    {
      do {
        try d.write(to: directories.preferences, options: .atomic)
      } catch {
        logger.error("Could not persist volume: \(error.localizedDescription, privacy: .private)")
      }
    }
  }
  private func refreshNowPlaying() {
    guard isRunning, playbackHasStarted else { return }
    let actualRate = player?.timeControlStatus == .playing ? Double(player?.rate ?? 0) : 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: activeTitle, MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: actualRate,
    ]
    MPNowPlayingInfoCenter.default().playbackState = actualRate > 0 ? .playing : .paused
  }
  private func refreshNowPlayingTime(force: Bool = false) {
    guard playbackHasStarted else { return }
    let now = Date()
    guard force || now.timeIntervalSince(lastNowPlayingTimeUpdate) >= 5 else { return }
    lastNowPlayingTimeUpdate = now
    guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
    let actualRate = player?.timeControlStatus == .playing ? Double(player?.rate ?? 0) : 0
    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    info[MPNowPlayingInfoPropertyPlaybackRate] = actualRate
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = actualRate > 0 ? .playing : .paused
  }
  private func clearNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }
  private var commandsInstalled = false

  private func installRemoteCommands() {
    guard !commandsInstalled else { return }
    commandsInstalled = true
    let center = MPRemoteCommandCenter.shared()

    func register(
      _ command: MPRemoteCommand,
      handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
      let token = command.addTarget(handler: handler)
      remoteCommandTargets.append((command, token))
    }

    register(center.playCommand) { [weak self] _ in
      Task { @MainActor in self?.play() }
      return .success
    }
    register(center.pauseCommand) { [weak self] _ in
      Task { @MainActor in self?.pause() }
      return .success
    }
    register(center.togglePlayPauseCommand) { [weak self] _ in
      Task { @MainActor in self?.togglePlayPause() }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [10]
    register(center.skipBackwardCommand) { [weak self] _ in
      Task { @MainActor in self?.seekRelative(-10) }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [10]
    register(center.skipForwardCommand) { [weak self] _ in
      Task { @MainActor in self?.seekRelative(10) }
      return .success
    }
    register(center.changePlaybackPositionCommand) { [weak self] event in
      if let event = event as? MPChangePlaybackPositionCommandEvent {
        Task { @MainActor in self?.commitSeek(to: event.positionTime) }
      }
      return .success
    }
  }

  private func uninstallRemoteCommands() {
    for (command, target) in remoteCommandTargets {
      command.removeTarget(target)
    }
    remoteCommandTargets.removeAll(keepingCapacity: false)
    commandsInstalled = false
  }

  /// AppModel owns one PlaybackController for the application lifetime. Normal
  /// stop/start cycles keep media commands registered once; confirmed process
  /// termination removes every target deterministically.
  func shutdown() {
    stop()
    uninstallRemoteCommands()
  }

}

private enum CuelixaPlaybackError: LocalizedError {
  case missingOrNonRegularFile
  case unreadableFile
  case emptyFile
  case assetPreparationTimedOut
  case assetNotPlayable
  case invalidDuration
  case noAudioTrack
  case itemPreparationTimedOut
  case seekFailed
  case seekTimedOut
  case playbackStartTimedOut(reason: String)

  var errorDescription: String? {
    switch self {
    case .missingOrNonRegularFile:
      "The lesson file is missing or is not a regular local file. Restore the file and try again."
    case .unreadableFile:
      "Cuelixa can’t read this lesson file. Check its permissions and try again."
    case .emptyFile:
      "This lesson file is empty and can’t be played."
    case .assetPreparationTimedOut:
      "AVFoundation did not finish inspecting this lesson in time. The library remains available; try the file again or test another known-good audio file."
    case .assetNotPlayable:
      "AVFoundation reports that this lesson isn’t playable on this Mac."
    case .invalidDuration:
      "This lesson doesn’t contain a valid finite playback duration."
    case .noAudioTrack:
      "This file doesn’t contain an audio track that Cuelixa can play."
    case .itemPreparationTimedOut:
      "AVFoundation did not make this lesson ready for playback in time."
    case .seekFailed:
      "The lesson could not be positioned for playback."
    case .seekTimedOut:
      "The lesson did not finish seeking in time."
    case .playbackStartTimedOut(let reason):
      reason == "none"
        ? "AVFoundation prepared the lesson but playback did not begin or advance in time."
        : "AVFoundation prepared the lesson but playback did not begin or advance in time (waiting reason: \(reason))."
    }
  }
}
