// SPDX-License-Identifier: Apache-2.0
import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "Application")
  let directories: AppDirectories
  @Published private(set) var section: LibrarySection = .all
  @Published private(set) var query = ""
  @Published var tracks: [Track] = []
  @Published var counts = LibraryCounts()
  @Published private(set) var readySubtitleHashes: Set<String> = []
  @Published private(set) var missingSubtitleCount = 0
  @Published var missingPrompt: Track?
  @Published var preparation: PreparationPresentation?
  @Published var completionTrack: Track?
  @Published var batch = BatchPresentation()
  @Published var quitWarning = false
  @Published private(set) var isImporting = false
  @Published private(set) var subtitleOverlayEnabled = true

  let db: LibraryDatabase
  lazy var scanner = LibraryScanner(
    db: db, directories: directories,
    onError: { [weak self] detail in self?.presentLibraryError(detail) })
  let cache: TranscriptCache
  lazy var cacheVerifier = TranscriptAvailabilityWorker(cache: cache)
  lazy var transcriber = NativeTranscriber(cache: cache, stagingDirectory: directories.staging)
  let player: PlaybackController
  let importCoordinator: ImportCoordinator
  weak var mainWindow: NSWindow?
  private var libraryMonitor: LibraryChangeMonitor?
  private var scanFallbackTimer: Timer?
  private var dialogSheets: DialogSheetController?
  private var subtitleOverlay: SubtitleOverlayController?
  private var quitSheet: QuitSheetController?
  private var started = false
  private var preparationToken: NativeTranscriber.Token?
  private var preparationHash: String?
  private var batchGeneration = 0
  private var batchTotal = 0
  private var batchDoneCount = 0
  private var batchErrorCount = 0
  private var batchCancelledCount = 0
  private var batchCancelRequested = false
  private var batchCurrentHash: String?
  private var batchCurrentTitle = ""
  private var batchCurrentPercent: Int?
  private var batchTitles: [String: String] = [:]
  private var batchOrder: [String] = []
  private var batchTokens: [String: NativeTranscriber.Token] = [:]
  private var batchPreflightTask: Task<Void, Never>?
  private var playAfterPreparationHash: String?
  private var pendingPlaybackFailure: String?
  private var confirmedQuitInProgress = false
  private var importTasks: [UUID: Task<Void, Never>] = [:]
  private var importBatchCount = 0
  private var subtitleRefreshTask: Task<Void, Never>?
  private var subtitleRefreshGeneration = 0
  private var subtitleStatusOverrides: [String: Bool] = [:]
  private var libraryErrorPresented = false

  init(directories: AppDirectories = AppPaths.current) {
    self.directories = directories
    db = LibraryDatabase(url: directories.database)
    cache = TranscriptCache(directories: directories)
    player = PlaybackController(directories: directories)
    importCoordinator = ImportCoordinator(directories: directories)
    player.onPositionSave = { [weak self] hash, pos in
      self?.db.setPosition(hash: hash, position: pos)
    }
    player.onEnded = { [weak self] hash in
      guard let self, let track = self.db.track(hash: hash) else { return }
      self.completionTrack = track
      self.updateMainWindowInteraction()
      if self.dialogSheets == nil { self.dialogSheets = DialogSheetController(model: self) }
      self.resolveMainWindow()?.makeKeyAndOrderFront(nil)
      if !self.quitWarning { self.dialogSheets?.showCompletion(track: track) }
    }
    player.onPlaybackStarted = { [weak self] in
      self?.presentStartedPlayback()
    }
    player.onPlaybackFailed = { [weak self] detail in
      self?.presentPlaybackFailure(detail)
    }
    player.onSubtitleChanged = { [weak self] _ in
      self?.refreshPlaybackOverlay()
    }
    player.onPresentationChanged = { [weak self] in
      self?.refreshPlaybackOverlay()
    }
    player.onActivity = { [weak self] in
      self?.subtitleOverlay?.revealControls()
    }
  }

  /// Resolve the single SwiftUI-owned library window on demand. The reference is
  /// weak so AppModel never owns an AppKit window lifecycle, but player/sheet
  /// transitions don't depend on one launch-time capture succeeding.
  func resolveMainWindow() -> NSWindow? {
    if let mainWindow { return mainWindow }
    let candidate =
      NSApp.mainWindow
      ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain })
    if let candidate { mainWindow = candidate }
    return candidate
  }

  func start() {
    guard !started else { return }
    started = true
    do {
      try directories.ensure()
    } catch {
      presentFatalStartupError(
        title: "Cuelixa couldn’t prepare its folders", detail: error.localizedDescription)
      return
    }
    if let databaseError = db.initializationError {
      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "Cuelixa couldn’t open the library database"
      alert.informativeText = databaseError
      alert.addButton(withTitle: "Quit")
      if let mainWindow = resolveMainWindow() {
        alert.beginSheetModal(for: mainWindow) { _ in NSApp.terminate(nil) }
      } else {
        alert.runModal()
        NSApp.terminate(nil)
      }
      return
    }
    // Start observation before the initial scan. If the library changes while
    // that first reconciliation is running, the scanner coalesces one follow-up
    // pass instead of leaving a startup race window.
    let monitor = LibraryChangeMonitor(root: directories.library) { [weak self] event in
      self?.handleLibraryChange(event)
    }
    if monitor.start() {
      libraryMonitor = monitor
    } else {
      installFallbackScanTimer()
    }
    refreshAndScan()
    presentLegacyLibraryIssueIfNeeded()
  }

  private func presentFatalStartupError(title: String, detail: String) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = title
    alert.informativeText = detail
    alert.addButton(withTitle: "Quit")
    if let mainWindow = resolveMainWindow() {
      alert.beginSheetModal(for: mainWindow) { _ in NSApp.terminate(nil) }
    } else {
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  private func presentLegacyLibraryIssueIfNeeded() {
    guard let issue = directories.legacyLibraryIssue else { return }
    let key = "DidExplainLegacyLibraryFallback"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    UserDefaults.standard.set(true, forKey: key)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Cuelixa used the safe library folder"
    alert.informativeText = issue.userMessage
    alert.addButton(withTitle: "OK")
    if let window = resolveMainWindow() {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  private func presentLibraryError(_ detail: String) {
    guard !libraryErrorPresented, !confirmedQuitInProgress else { return }
    libraryErrorPresented = true
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Cuelixa couldn’t scan the lesson library"
    alert.informativeText = detail
    alert.addButton(withTitle: "OK")
    if let window = resolveMainWindow() {
      alert.beginSheetModal(for: window) { [weak self] _ in
        self?.libraryErrorPresented = false
      }
    } else {
      alert.runModal()
      libraryErrorPresented = false
    }
  }

  private func installFallbackScanTimer() {
    guard scanFallbackTimer == nil else { return }
    // FSEvents is the normal path. This low-frequency, tolerant timer exists
    // only as a correctness fallback when the native event stream cannot run.
    scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.refreshAndScan() }
    }
    scanFallbackTimer?.tolerance = 30
  }

  private func handleLibraryChange(_ event: LibraryChangeEvent) {
    guard !confirmedQuitInProgress else { return }
    if event.mustRescan {
      logger.notice("FSEvents requested a full library reconciliation")
    }
    if event.rootChanged {
      // WatchRoot means the monitored path (or a parent) moved/deleted. Cuelixa's
      // contract is the selected Cuelixa library root, so recreate it and restart the
      // stream before reconciling the hierarchy.
      do {
        try directories.ensure()
      } catch {
        logger.error(
          "Could not recreate the library root after RootChanged: \(error.localizedDescription, privacy: .private)"
        )
        presentLibraryError("The lesson library folder could not be recreated.")
        return
      }
      if libraryMonitor?.restart() != true {
        libraryMonitor = nil
        installFallbackScanTimer()
      }
    }
    refreshAndScan()
  }

  func refreshAndScan() {
    guard !confirmedQuitInProgress else { return }
    scanner.scan { [weak self] in
      self?.refreshLibraryState()
    }
  }

  /// A filesystem reconciliation can change the track set and subtitle-cache
  /// membership, so it is the one broad refresh boundary.
  private func refreshLibraryState() {
    tracks = db.tracks(section: section, query: query)
    counts = db.counts()
    let allTracks = db.tracks(section: .all, query: "")
    let hashes = allTracks.map(\.contentHash)

    subtitleRefreshGeneration &+= 1
    let generation = subtitleRefreshGeneration
    subtitleRefreshTask?.cancel()
    subtitleRefreshTask = Task { @MainActor [weak self, allTracks, hashes] in
      guard let self else { return }
      let verified = await self.cacheVerifier.verifiedHashes(allTracks)
      guard !Task.isCancelled, generation == self.subtitleRefreshGeneration else { return }
      let libraryHashes = Set(hashes)
      var ready = verified
      for (hash, isReady) in self.subtitleStatusOverrides where libraryHashes.contains(hash) {
        if isReady {
          ready.insert(hash)
        } else {
          ready.remove(hash)
        }
      }
      self.subtitleStatusOverrides.removeAll(keepingCapacity: true)
      self.readySubtitleHashes = ready
      self.missingSubtitleCount = max(0, hashes.count - ready.count)
      self.subtitleRefreshTask = nil
    }
  }

  /// Playback/completion changes affect DB-derived browsing state but not the
  /// transcript filesystem. Keep them away from O(n) cache verification.
  private func refreshBrowsingState() {
    tracks = db.tracks(section: section, query: query)
    counts = db.counts()
  }

  /// A completed transcription has one known cache identity. Revalidate only
  /// that hash and update the aggregate count without walking every transcript.
  private func refreshSubtitleStatus(hash: String) {
    let isReady = cache.verified(hash: hash)
    subtitleStatusOverrides[hash] = isReady
    if isReady {
      readySubtitleHashes.insert(hash)
    } else {
      readySubtitleHashes.remove(hash)
    }
    missingSubtitleCount = max(0, counts.all - readySubtitleHashes.count)
  }

  func subtitleReady(_ track: Track) -> Bool {
    readySubtitleHashes.contains(track.contentHash)
  }

  var canResetPreparedSubtitles: Bool {
    !confirmedQuitInProgress && preparation == nil && !batch.active
  }

  func resetPreparedSubtitles() {
    guard canResetPreparedSubtitles else { return }

    subtitleRefreshGeneration &+= 1
    subtitleRefreshTask?.cancel()
    subtitleRefreshTask = nil
    subtitleStatusOverrides.removeAll(keepingCapacity: false)

    do {
      try cache.resetManagedTranscripts()
      batch = BatchPresentation()
      refreshLibraryState()
    } catch {
      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "Cuelixa couldn’t reset prepared subtitles"
      alert.informativeText = error.localizedDescription
      alert.addButton(withTitle: "OK")
      if let window = resolveMainWindow() {
        alert.beginSheetModal(for: window)
      } else {
        alert.runModal()
      }
    }
  }

  /// Search and section changes only affect the visible query. Avoid rechecking
  /// every subtitle manifest/hash on each search keystroke; full refreshes are
  /// reserved for library, playback-state, and transcription changes.
  private func refreshVisibleTracks() {
    tracks = db.tracks(section: section, query: query)
  }

  func setSection(_ s: LibrarySection) {
    section = s
    refreshVisibleTracks()
  }
  func setQuery(_ s: String) {
    query = s
    refreshVisibleTracks()
  }

  func playTrack(_ track: Track) {
    guard !confirmedQuitInProgress, completionTrack == nil else { return }
    guard FileManager.default.fileExists(atPath: track.path) else {
      presentPlaybackFailure(
        "The lesson file is no longer available. Restore it to the Library Folder or remove the missing lesson and try again."
      )
      return
    }
    if let subtitleURL = playbackSubtitleURL(for: track) {
      startPlayback(track, srt: subtitleURL)
    } else {
      missingPrompt = track
      if dialogSheets == nil { dialogSheets = DialogSheetController(model: self) }
      dialogSheets?.showMissing(track: track)
    }
  }
  /// Prefer Cuelixa's verified durable transcript, but also honor a valid
  /// user-owned sidecar SRT next to the audio file. This keeps library-folder
  /// imports unsurprising and lets existing subtitle collections play without
  /// destructive migration or duplicate transcription.
  private func playbackSubtitleURL(for track: Track) -> URL? {
    if let cached = cache.verifiedSRTURL(hash: track.contentHash) { return cached }
    return SRT.validSidecarURL(forAudioPath: track.path)
  }

  func dismissMissing() {
    missingPrompt = nil
    dialogSheets?.hideMissing()
    showLibraryWindow()
  }
  func playWithoutSubtitles(_ track: Track) {
    missingPrompt = nil
    dialogSheets?.hideMissing()
    startPlayback(track, srt: nil)
  }
  func prepareAndPlay(_ track: Track) {
    missingPrompt = nil
    dialogSheets?.hideMissing()
    playAfterPreparationHash = track.contentHash
    prepareTrack(track)
  }
  func prepareTrack(_ track: Track) {
    guard !confirmedQuitInProgress else { return }
    if let previousHash = preparationHash, let previousToken = preparationToken {
      _ = transcriber.cancel(hash: previousHash, token: previousToken)
    }

    let presentation = PreparationPresentation(hash: track.contentHash, title: track.title)
    preparationHash = track.contentHash
    preparationToken = nil
    preparation = presentation
    if dialogSheets == nil { dialogSheets = DialogSheetController(model: self) }
    dialogSheets?.showPreparation(presentation)

    let token = transcriber.request(
      track: track,
      progress: { [weak self] msg, pct in
        guard let self, self.preparationHash == track.contentHash,
          var current = self.preparation, current.hash == track.contentHash
        else { return }

        // Speech can report many fine-grained progress values. Publishing every
        // single percent through the app-wide ObservableObject needlessly
        // recomputes the library while transcription is already doing expensive
        // on-device work. Preserve meaningful status changes while coalescing
        // numerical progress to 2-point steps.
        let presentedPercent = pct.map { value in
          value >= 100 ? 100 : max(1, (value / 2) * 2)
        }
        if current.status == msg, current.percent == presentedPercent { return }
        current.status = msg
        current.percent = presentedPercent
        self.preparation = current
      },
      completion: { [weak self] result in
        guard let self, self.preparationHash == track.contentHash else { return }
        self.preparationToken = nil
        switch result {
        case .success:
          self.preparation = nil
          self.preparationHash = nil
          self.dialogSheets?.hidePreparation()
          if self.playAfterPreparationHash == track.contentHash {
            if self.confirmedQuitInProgress {
              self.playAfterPreparationHash = nil
            } else if !self.resumePreparedPlaybackIfPossible() {
              self.showLibraryWindow()
            }
          } else {
            self.showLibraryWindow()
          }
          self.refreshSubtitleStatus(hash: track.contentHash)
        case .failure(let error):
          if self.isCancellation(error) {
            self.preparation = nil
            self.preparationHash = nil
            self.dialogSheets?.hidePreparation()
          } else if var current = self.preparation, current.hash == track.contentHash {
            current.failed = true
            current.error = error.localizedDescription
            current.status = "Could not prepare subtitles"
            current.percent = nil
            self.preparation = current
          }
          if self.playAfterPreparationHash == track.contentHash {
            self.playAfterPreparationHash = nil
          }
        }
      })
    if preparationHash == track.contentHash { preparationToken = token }
  }

  func cancelSinglePreparation() {
    if let hash = preparationHash, let token = preparationToken {
      _ = transcriber.cancel(hash: hash, token: token)
    } else if let hash = preparationHash, transcriber.isPending(hash: hash) {
      _ = transcriber.cancel(hash: hash, token: nil)
    }
    preparationToken = nil
    preparationHash = nil
    preparation = nil
    dialogSheets?.hidePreparation()
    playAfterPreparationHash = nil
    showLibraryWindow()
  }

  func prepareAll() {
    guard !confirmedQuitInProgress, !batch.active, batchPreflightTask == nil else { return }
    subtitleRefreshGeneration &+= 1
    subtitleRefreshTask?.cancel()
    subtitleRefreshTask = nil
    subtitleStatusOverrides.removeAll(keepingCapacity: true)
    batchCancelRequested = false
    batchTotal = 0
    batchDoneCount = 0
    batchErrorCount = 0
    batchCancelledCount = 0
    batchCurrentHash = nil
    batchCurrentTitle = ""
    batchCurrentPercent = nil
    batchTitles = [:]
    batchOrder = []
    batchTokens = [:]

    let all = db.tracks(section: .all, query: "")
    batchGeneration += 1
    let generation = batchGeneration
    batch = BatchPresentation(
      visible: true, cancelled: false, cancelling: false, active: true,
      title: "Checking local subtitles", count: "",
      track: "Verifying existing subtitle caches",
      detail: "This check runs away from the main AppKit event loop.", progress: nil)

    batchPreflightTask = Task { @MainActor [weak self, all] in
      guard let self else { return }
      let verifiedHashes = await self.cacheVerifier.verifiedHashes(all)
      guard !Task.isCancelled, !self.confirmedQuitInProgress, generation == self.batchGeneration
      else { return }
      self.batchPreflightTask = nil
      self.beginPreparedBatch(all: all, verifiedHashes: verifiedHashes, generation: generation)
    }
  }

  private func beginPreparedBatch(
    all: [Track], verifiedHashes: Set<String>, generation: Int
  ) {
    guard generation == batchGeneration, batch.active else { return }
    readySubtitleHashes = verifiedHashes
    let candidates = all.filter { !verifiedHashes.contains($0.contentHash) }
    missingSubtitleCount = candidates.count
    guard !candidates.isEmpty else {
      batch = BatchPresentation(
        visible: true, cancelled: false, cancelling: false, active: false,
        title: "All subtitles are ready",
        count: "\(all.count) of \(all.count)",
        track: "Every lesson already has a verified local subtitle cache.",
        detail: "Nothing was reprocessed.",
        progress: 1)
      refreshBrowsingState()
      return
    }

    batchTotal = candidates.count
    batchDoneCount = 0
    batchErrorCount = 0
    batchCancelledCount = 0
    batchCancelRequested = false
    batchCurrentHash = nil
    batchCurrentTitle = ""
    batchCurrentPercent = nil
    batchTitles = Dictionary(uniqueKeysWithValues: candidates.map { ($0.contentHash, $0.title) })
    batchOrder = candidates.map(\.contentHash)
    batchTokens = [:]

    let ready = max(0, all.count - candidates.count)
    batch = BatchPresentation(
      visible: true, cancelled: false, cancelling: false, active: true,
      title: "Preparing subtitles",
      count: "0 of \(candidates.count)",
      track: "Queued \(candidates.count) lesson\(candidates.count == 1 ? "" : "s")",
      detail: "\(ready) already verified · one local transcription at a time",
      progress: 0)

    for track in candidates {
      let hash = track.contentHash
      let title = track.title
      let token = transcriber.request(
        track: track,
        progress: { [weak self] message, percent in
          self?.batchProgress(
            generation: generation, hash: hash, title: title, message: message, percent: percent)
        },
        completion: { [weak self] result in
          guard let self else { return }
          switch result {
          case .success:
            self.batchDone(generation: generation, hash: hash)
          case .failure(let error):
            self.batchError(generation: generation, hash: hash, error: error)
          }
        })
      if let token, generation == batchGeneration, batch.active {
        batchTokens[hash] = token
      }
    }
  }

  func cancelBatch() {
    guard batch.active, !batchCancelRequested else { return }
    batchCancelRequested = true

    if let preflight = batchPreflightTask {
      preflight.cancel()
      batchPreflightTask = nil
      batch = BatchPresentation(
        visible: true, cancelled: true, cancelling: false, active: false,
        title: "Subtitle preparation cancelled", count: "",
        track: "No transcription work was started.",
        detail: "The local cache check was cancelled.", progress: nil)
      return
    }

    var cancellingPresentation = batch
    cancellingPresentation.cancelling = true
    if batch != cancellingPresentation { batch = cancellingPresentation }
    renderBatchStatus(message: "Cancelling…")
    let requests: [(String, NativeTranscriber.Token?)] = batchOrder.compactMap { hash in
      guard let token = batchTokens[hash] else { return nil }
      return (hash, token)
    }
    _ = transcriber.cancelMany(requests)
    if batch.active { renderBatchStatus(message: "Cancelling…") }
  }

  private func batchProgress(
    generation: Int, hash: String, title: String, message: String, percent: Int?
  ) {
    guard generation == batchGeneration, batch.active else { return }
    if batchCancelRequested {
      renderBatchStatus(message: "Cancelling…")
      return
    }

    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // The batch already exposes its queue count. Re-publishing the same app-wide
    // state once for every enqueued lesson only causes redundant SwiftUI work.
    if normalized == "queued" || normalized == "already queued" { return }

    let presentedPercent = percent.map { value in
      value >= 100 ? 100 : max(1, (value / 2) * 2)
    }
    if batchCurrentHash == hash, batchCurrentTitle == title,
      batchCurrentPercent == presentedPercent
    {
      return
    }
    batchCurrentHash = hash
    batchCurrentTitle = title
    batchCurrentPercent = presentedPercent
    renderBatchStatus(message: message)
  }

  private func renderBatchStatus(message: String = "") {
    guard batch.active, batchTotal > 0 else { return }
    let processed = batchDoneCount + batchErrorCount + batchCancelledCount
    let currentFraction: Double
    if batchCurrentHash != nil, let percent = batchCurrentPercent {
      currentFraction = max(0, min(1, Double(percent) / 100.0))
    } else {
      currentFraction = 0
    }
    let fraction = min(1, (Double(processed) + currentFraction) / Double(batchTotal))
    let currentNumber = batchCurrentHash == nil ? processed : min(batchTotal, processed + 1)
    let remaining = max(0, batchTotal - processed - (batchCurrentHash == nil ? 0 : 1))
    let trackText = batchCurrentTitle.isEmpty ? "Queued \(batchTotal) lessons" : batchCurrentTitle

    var detailBits: [String] = []
    if batchCancelRequested {
      detailBits.append("Stopping current transcription and clearing queued work")
    }
    if batchCurrentHash != nil, !batchCancelRequested {
      if let percent = batchCurrentPercent {
        detailBits.append("\(percent)% current lesson")
      } else {
        detailBits.append("Processing locally")
      }
    }
    if remaining > 0 { detailBits.append("\(remaining) remaining") }
    if batchDoneCount > 0 { detailBits.append("\(batchDoneCount) ready") }
    if batchCancelledCount > 0 { detailBits.append("\(batchCancelledCount) cancelled") }
    if batchErrorCount > 0 { detailBits.append("\(batchErrorCount) failed") }
    if detailBits.isEmpty {
      detailBits.append(message.isEmpty ? "Waiting for local transcription" : message)
    }

    let updated = BatchPresentation(
      visible: batch.visible,
      cancelled: batch.cancelled,
      cancelling: batch.cancelling,
      active: true,
      title: batchCancelRequested ? "Cancelling subtitle preparation" : "Preparing subtitles",
      count: "\(currentNumber) of \(batchTotal)",
      track: trackText,
      detail: detailBits.joined(separator: " · "),
      progress: fraction
    )
    if batch != updated { batch = updated }
  }

  private func batchDone(generation: Int, hash: String) {
    guard generation == batchGeneration, batch.active else { return }
    batchTokens.removeValue(forKey: hash)
    batchDoneCount += 1
    if batchCurrentHash == hash { clearBatchCurrent() }
    refreshSubtitleStatus(hash: hash)
    finishOrAdvanceBatch()
  }

  private func batchError(generation: Int, hash: String, error: Error) {
    guard generation == batchGeneration, batch.active else { return }
    batchTokens.removeValue(forKey: hash)
    if isCancellation(error) {
      batchCancelledCount += 1
    } else {
      batchErrorCount += 1
    }
    if batchCurrentHash == hash { clearBatchCurrent() }
    finishOrAdvanceBatch()
  }

  private func finishOrAdvanceBatch() {
    let processed = batchDoneCount + batchErrorCount + batchCancelledCount
    guard processed >= batchTotal else {
      renderBatchStatus(message: "Advancing to next lesson")
      return
    }

    batchTokens = [:]
    clearBatchCurrent()

    let finalPresentation: BatchPresentation
    if batchCancelRequested {
      finalPresentation = BatchPresentation(
        visible: true, cancelled: true, cancelling: false, active: false,
        title: "Subtitle preparation cancelled", count: "",
        track: "\(batchDoneCount) ready · \(batchCancelledCount) cancelled",
        detail: "Completed subtitle sets were kept. Cancelled lessons can be prepared later.",
        progress: 0)
    } else if batchErrorCount > 0 {
      finalPresentation = BatchPresentation(
        visible: true, cancelled: false, cancelling: false, active: false,
        title: "Subtitle preparation finished", count: "\(processed) of \(batchTotal)",
        track: "\(batchDoneCount) ready · \(batchErrorCount) failed",
        detail: "Failed lessons were left uncached and can be retried with Prepare All.",
        progress: 1)
    } else {
      finalPresentation = BatchPresentation(
        visible: true, cancelled: false, cancelling: false, active: false,
        title: "All subtitles are ready", count: "\(batchTotal) of \(batchTotal)",
        track: "Verified local subtitle caches are ready for every queued lesson.",
        detail: "Already-valid subtitles were skipped without reprocessing.",
        progress: 1)
    }
    batch = finalPresentation

    // Titles/order are only needed while the batch is active. Release them as
    // soon as the summary is materialized instead of retaining an entire library
    // worth of temporary queue metadata until the next Prepare All operation.
    batchTitles.removeAll(keepingCapacity: false)
    batchOrder.removeAll(keepingCapacity: false)
    refreshBrowsingState()
  }

  private func clearBatchCurrent() {
    batchCurrentHash = nil
    batchCurrentTitle = ""
    batchCurrentPercent = nil
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? CuelixaError) == .cancelled
  }

  func hideBatch() { if !batch.active { batch = BatchPresentation() } }

  private func startPlayback(_ track: Track, srt: URL?) {
    guard !confirmedQuitInProgress, !quitWarning, completionTrack == nil else { return }

    // Playback preparation and the first play request are asynchronous. Keep the
    // library visible until PlaybackController proves both a playing time-control
    // state and actual timeline advancement.
    guard player.start(track: track, subtitleURL: srt) else {
      showLibraryWindow()
      return
    }
    resolveMainWindow()?.makeKeyAndOrderFront(nil)
    updateMainWindowInteraction()
  }

  private func presentStartedPlayback() {
    guard !confirmedQuitInProgress, !quitWarning, completionTrack == nil, player.isPlaying else {
      return
    }
    // Restore Cuelixa's original product contract: once playback is genuinely
    // proven, the library gets out of the way and a movable subtitle/transport
    // overlay becomes the playback surface. The overlay never owns AVPlayer.
    resolveMainWindow()?.orderOut(nil)
    refreshPlaybackOverlay(forcePresent: true)
    updateMainWindowInteraction()
  }
  @discardableResult
  private func resumePreparedPlaybackIfPossible() -> Bool {
    guard !confirmedQuitInProgress, !quitWarning, completionTrack == nil,
      missingPrompt == nil, preparation == nil, let hash = playAfterPreparationHash
    else { return false }
    guard let subtitleURL = cache.verifiedSRTURL(hash: hash),
      let track = db.track(hash: hash), !track.missing, !track.path.isEmpty
    else {
      playAfterPreparationHash = nil
      return false
    }
    let audioURL = URL(fileURLWithPath: track.path)
    guard let currentSignature = fileSignature(audioURL),
      let known = db.fileSignature(path: track.path), known.0 == hash,
      known.1 == currentSignature
    else {
      playAfterPreparationHash = nil
      return false
    }
    playAfterPreparationHash = nil
    startPlayback(track, srt: subtitleURL)
    return true
  }
  func stopPlayback(showLibrary: Bool = true, savePosition: Bool = true) {
    player.stop(save: savePosition)
    subtitleOverlay?.hide()
    if showLibrary { showLibraryWindow() }
    refreshBrowsingState()
  }
  func showLibraryWindow() {
    NSApp.activate()
    if confirmedQuitInProgress { return }
    if quitWarning {
      quitSheet?.focus()
      return
    }
    if let completionTrack {
      resolveMainWindow()?.makeKeyAndOrderFront(nil)
      if dialogSheets == nil { dialogSheets = DialogSheetController(model: self) }
      dialogSheets?.showCompletion(track: completionTrack)
      return
    }
    if missingPrompt != nil || preparation != nil {
      resolveMainWindow()?.makeKeyAndOrderFront(nil)
      dialogSheets?.focusActive()
      return
    }
    resolveMainWindow()?.makeKeyAndOrderFront(nil)
    presentPendingPlaybackFailureIfPossible()
  }
  func updateMainWindowInteraction() {
    // AppKit sheets own modality/focus. Playback UI is an independent floating
    // nonactivating panel, mirroring Cuelixa's Linux overlay-first workflow.
  }
  func togglePlayPause() { player.togglePlayPause() }

  func toggleSubtitleOverlay() {
    subtitleOverlayEnabled.toggle()
    if subtitleOverlayEnabled {
      refreshPlaybackOverlay(forcePresent: player.isRunning)
    } else {
      subtitleOverlay?.hide()
    }
  }

  private func ensurePlaybackOverlay() -> SubtitleOverlayController {
    if let subtitleOverlay { return subtitleOverlay }
    let overlay = SubtitleOverlayController(
      onPlayPause: { [weak self] in self?.player.togglePlayPause() },
      onBack10: { [weak self] in self?.player.seekRelative(-10) },
      onForward10: { [weak self] in self?.player.seekRelative(10) },
      onBeginScrub: { [weak self] value in self?.player.beginScrub(value) },
      onLiveScrub: { [weak self] value in self?.player.liveScrub(value) },
      onEndScrub: { [weak self] value in self?.player.endScrub(value) },
      onStop: { [weak self] in self?.stopPlayback(showLibrary: true) }
    )
    subtitleOverlay = overlay
    return overlay
  }

  private func refreshPlaybackOverlay(forcePresent: Bool = false) {
    guard subtitleOverlayEnabled, player.isRunning else {
      subtitleOverlay?.hide()
      return
    }
    let overlay = ensurePlaybackOverlay()
    let presentation = SubtitleOverlayController.Presentation(
      subtitle: player.subtitleText,
      position: player.position,
      duration: player.duration,
      playing: player.isPlaybackRequested
    )
    if forcePresent {
      overlay.present(presentation, screen: resolveMainWindow()?.screen)
    } else {
      overlay.update(presentation)
    }
  }
  func finishCurrent(completed: Bool) {
    guard let t = completionTrack else { return }
    let usefulResume = max(0, min(player.position, max(0, player.duration - 2)))
    player.stop(save: false)
    if completed {
      db.markCompleted(hash: t.contentHash, completed: true)
    } else {
      db.setPosition(hash: t.contentHash, position: usefulResume)
    }
    completionTrack = nil
    updateMainWindowInteraction()
    dialogSheets?.hideCompletion()
    if !resumePreparedPlaybackIfPossible() { showLibraryWindow() }
    refreshBrowsingState()
  }
  func replayCurrent() {
    guard let t = completionTrack else { return }
    let hasSuspendedDialog = missingPrompt != nil || preparation != nil
    playAfterPreparationHash = nil
    completionTrack = nil
    dialogSheets?.hideCompletion()
    updateMainWindowInteraction()
    db.resetPosition(hash: t.contentHash)
    resolveMainWindow()?.makeKeyAndOrderFront(nil)
    guard let fresh = db.track(hash: t.contentHash), !fresh.missing,
      FileManager.default.fileExists(atPath: fresh.path)
    else {
      showLibraryWindow()
      refreshBrowsingState()
      return
    }
    playTrack(fresh)
    if hasSuspendedDialog || missingPrompt != nil || preparation != nil {
      showLibraryWindow()
    }
  }
  func mark(_ track: Track, completed: Bool) {
    db.markCompleted(hash: track.contentHash, completed: completed)
    refreshBrowsingState()
  }
  func restart(_ track: Track) {
    guard !confirmedQuitInProgress else { return }
    if player.activeHash == track.contentHash {
      player.stop(save: false)
    }
    db.resetPosition(hash: track.contentHash)
    if let t = db.track(hash: track.contentHash) { playTrack(t) }
  }

  func importFiles(_ urls: [URL]) {
    guard !confirmedQuitInProgress else { return }
    let importID = UUID()

    importBatchCount += 1
    isImporting = true

    let task = Task { @MainActor [weak self, urls] in
      guard let self else { return }
      let summary = await self.importCoordinator.importFiles(urls)
      self.finishedImportBatch(importID)
      self.refreshAndScan()
      self.presentImportSummary(summary)
    }
    importTasks[importID] = task
  }

  private func presentImportSummary(_ summary: ImportSummary) {
    guard !confirmedQuitInProgress else { return }
    let alert = NSAlert()
    alert.alertStyle = summary.count(.failed) > 0 ? .warning : .informational
    alert.messageText = "Import completed with details"
    let counts = [
      "\(summary.count(.imported)) imported", "\(summary.count(.duplicate)) already present",
      "\(summary.count(.unsupported)) unsupported", "\(summary.count(.failed)) failed",
      "\(summary.count(.cancelled)) cancelled",
    ]
    let failures = summary.results.filter {
      $0.disposition == .failed || $0.disposition == .unsupported || $0.disposition == .cancelled
    }.prefix(8).map { result in
      "• \(result.sourceName): \(result.detail ?? result.disposition.rawValue)"
    }
    alert.informativeText =
      (counts.joined(separator: " · ") + "\n\n" + failures.joined(separator: "\n"))
    alert.addButton(withTitle: "OK")
    if let window = resolveMainWindow() {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  private func finishedImportBatch(_ importID: UUID) {
    importTasks.removeValue(forKey: importID)
    importBatchCount = max(0, importBatchCount - 1)
    isImporting = importBatchCount > 0
  }

  private func waitForImports() async {
    let tasks = Array(importTasks.values)
    for task in tasks {
      await task.value
    }
  }

  func openLibraryFolder() { NSWorkspace.shared.open(directories.library) }

  private func savePrefs() {
    do {
      try directories.ensure()
    } catch {
      logger.error(
        "Could not prepare preferences directory: \(error.localizedDescription, privacy: .private)")
      return
    }
    let o: [String: Any] = ["volume": player.volume]
    do {
      let data = try JSONSerialization.data(
        withJSONObject: o, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: directories.preferences, options: .atomic)
    } catch {
      logger.error(
        "Could not persist preferences: \(error.localizedDescription, privacy: .private)")
    }
  }
  func saveNow() {
    if player.isRunning, let h = player.activeHash {
      db.setPosition(hash: h, position: player.position)
    }
    savePrefs()
  }

  func requestQuit() {
    NSApp.terminate(nil)
  }

  private func presentPlaybackFailure(_ detail: String) {
    subtitleOverlay?.hide()
    refreshBrowsingState()
    guard !confirmedQuitInProgress else { return }
    pendingPlaybackFailure = detail
    showLibraryWindow()
  }

  private func presentPendingPlaybackFailureIfPossible() {
    guard !confirmedQuitInProgress, !quitWarning, missingPrompt == nil, preparation == nil,
      completionTrack == nil, let detail = pendingPlaybackFailure,
      let mainWindow = resolveMainWindow()
    else { return }
    pendingPlaybackFailure = nil
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Cuelixa couldn’t play this lesson"
    alert.informativeText = detail
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: mainWindow)
  }

  func handleTerminationRequest() {
    if confirmedQuitInProgress { return }
    if transcriber.pendingCount > 0 || batch.active {
      quitWarning = true
      dialogSheets?.suspendActive()
      if quitSheet == nil { quitSheet = QuitSheetController(model: self) }
      quitSheet?.show()
    } else {
      beginConfirmedTermination()
    }
  }

  func dismissQuitWarning() {
    quitWarning = false
    quitSheet?.hide()
    NSApp.reply(toApplicationShouldTerminate: false)
    if !resumePreparedPlaybackIfPossible() { showLibraryWindow() }
  }

  func confirmQuit() {
    beginConfirmedTermination()
  }

  private func beginConfirmedTermination() {
    guard !confirmedQuitInProgress else { return }
    confirmedQuitInProgress = true
    libraryMonitor?.stop()
    subtitleRefreshTask?.cancel()
    subtitleRefreshTask = nil
    batchPreflightTask?.cancel()
    batchPreflightTask = nil
    scanFallbackTimer?.invalidate()
    scanFallbackTimer = nil
    updateMainWindowInteraction()
    dialogSheets?.suspendActive()
    playAfterPreparationHash = nil
    pendingPlaybackFailure = nil
    quitWarning = false
    quitSheet?.hide()
    player.shutdown()
    subtitleOverlay?.shutdown()
    subtitleOverlay = nil
    // Begin cancelling Speech immediately, then wait for every owned background
    // operation before allowing AppKit to terminate the process.
    transcriber.cancelAll()
    for importTask in importTasks.values { importTask.cancel() }
    saveNow()
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.scanner.cancelAndWait()
      await self.transcriber.cancelAllAndWait()
      await self.waitForImports()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
  }

  var quitPreparationSummary: String {
    let pending = transcriber.pendingCount
    if batch.active, batchTotal > 0 {
      let processed = batchDoneCount + batchErrorCount + batchCancelledCount
      let current = min(batchTotal, processed + 1)
      let remaining = max(0, batchTotal - processed)
      if !batchCurrentTitle.isEmpty {
        return
          "Cuelixa is preparing \(current) of \(batchTotal): \(batchCurrentTitle). \(remaining) subtitle set\(remaining == 1 ? " remains." : "s remain.")"
      }
      let amount = remaining == 0 ? pending : remaining
      return
        "Cuelixa still has \(amount) subtitle set\(amount == 1 ? " to prepare." : "s to prepare.")"
    }
    if pending == 1 { return "Cuelixa is still preparing a subtitle set." }
    return "Cuelixa is still preparing \(pending) subtitle sets."
  }
}
