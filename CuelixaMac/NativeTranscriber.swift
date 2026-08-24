// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation

@MainActor
final class NativeTranscriber: ObservableObject {
  typealias Token = UUID
  typealias ProgressHandler = @MainActor (String, Int?) -> Void
  typealias CompletionHandler = @MainActor (Result<URL, Error>) -> Void

  @Published private(set) var isActive = false
  @Published private(set) var currentHash: String?

  private struct Watcher {
    let progress: ProgressHandler
    let completion: CompletionHandler
  }

  private final class Job {
    let id = UUID()
    let track: Track
    var watchers: [Token: Watcher]
    var lastProgress: (message: String, percent: Int?)?

    init(track: Track, token: Token, watcher: Watcher) {
      self.track = track
      self.watchers = [token: watcher]
    }
  }

  private let cache: TranscriptCache
  private let stagingDirectory: URL
  private let executor: any TranscriptionExecuting
  private var pending: [String: Job] = [:]
  private var queue: [Job] = []
  private var task: Task<Void, Never>?
  private var pacingTask: Task<Void, Never>?
  private var cancellingAll = false
  private var executorCancellationTask: Task<Void, Never>?
  private var activeJob: Job?

  init(
    cache: TranscriptCache, stagingDirectory: URL = AppPaths.current.staging,
    executor: any TranscriptionExecuting = AppleSpeechExecutor()
  ) {
    self.cache = cache
    self.stagingDirectory = stagingDirectory
    self.executor = executor
  }

  /// Queue one consumer for a subtitle job. Requests sharing the same content
  /// hash share the same underlying Apple Speech transcription and receive
  /// independent watcher tokens while preserving Cuelixa queue semantics.
  @discardableResult
  func request(
    track: Track,
    progress: @escaping ProgressHandler,
    completion: @escaping CompletionHandler
  ) -> Token? {
    if let url = cache.verifiedSRTURL(hash: track.contentHash) {
      completion(.success(url))
      return nil
    }
    guard FileManager.default.fileExists(atPath: track.path) else {
      completion(.failure(CuelixaError.missingAudio))
      return nil
    }

    let token = Token()
    let watcher = Watcher(progress: progress, completion: completion)
    if let existing = pending[track.contentHash] {
      existing.watchers[token] = watcher
      if let last = existing.lastProgress {
        progress(last.message, last.percent)
      } else {
        progress("Already queued", nil)
      }
      updateActivity()
      return token
    }

    let job = Job(track: track, token: token, watcher: watcher)
    pending[track.contentHash] = job
    queue.append(job)
    progress("Queued", nil)
    updateActivity()
    startNextIfNeeded()
    return token
  }

  var pendingCount: Int { pending.count }
  func isPending(hash: String) -> Bool { pending[hash] != nil }

  /// Cancel one consumer. The shared transcription is stopped only when its
  /// final watcher has been removed. token == nil deliberately cancels all
  /// watchers for the content hash.
  @discardableResult
  func cancel(hash: String, token: Token? = nil) -> Bool {
    guard let job = pending[hash] else { return false }

    let removed: [Watcher]
    if let token {
      guard let watcher = job.watchers.removeValue(forKey: token) else { return false }
      removed = [watcher]
    } else {
      removed = Array(job.watchers.values)
      job.watchers.removeAll()
    }

    for watcher in removed {
      watcher.completion(.failure(CuelixaError.cancelled))
    }

    if job.watchers.isEmpty {
      if pending[hash] === job { pending.removeValue(forKey: hash) }
      if activeJob === job {
        task?.cancel()
        if executorCancellationTask == nil {
          executorCancellationTask = Task { await executor.cancelAndWait() }
        }
      }
    }
    if pending.isEmpty, task == nil {
      pacingTask?.cancel()
      pacingTask = nil
    }
    updateActivity()
    if task == nil, pacingTask == nil, !cancellingAll { startNextIfNeeded() }
    return true
  }

  @discardableResult
  func cancelMany(_ requests: [(String, Token?)]) -> Int {
    var count = 0
    var seen = Set<CancelKey>()
    for (hash, token) in requests {
      let key = CancelKey(hash: hash, token: token)
      guard seen.insert(key).inserted else { continue }
      if cancel(hash: hash, token: token) { count += 1 }
    }
    return count
  }

  func cancelAll() {
    cancellingAll = true
    pacingTask?.cancel()
    pacingTask = nil
    let hashes = Array(pending.keys)
    for hash in hashes { _ = cancel(hash: hash, token: nil) }
    queue.removeAll()
    cancellingAll = false
    updateActivity()
  }

  /// Cancel every watcher and wait for the active analyzer task to finish its
  /// cancellation/cleanup path before the application process is released.
  func cancelAllAndWait() async {
    let activeTask = task
    cancelAll()
    let cancellationTask = executorCancellationTask
    if let activeTask { await activeTask.value }
    if let cancellationTask { await cancellationTask.value }
    executorCancellationTask = nil
  }

  // Compatibility wrapper for code that only needs a fire-and-callback request.
  @discardableResult
  func prepare(
    track: Track,
    progress: @escaping ProgressHandler,
    completion: @escaping CompletionHandler
  ) -> Token? {
    request(track: track, progress: progress, completion: completion)
  }

  private struct CancelKey: Hashable {
    let hash: String
    let token: Token?
  }

  private func updateActivity() {
    let active = task != nil || pacingTask != nil || !pending.isEmpty
    if isActive != active { isActive = active }
  }

  private func startNextIfNeeded() {
    guard task == nil, pacingTask == nil else { return }

    while !queue.isEmpty {
      let job = queue.removeFirst()
      guard pending[job.track.contentHash] === job, !job.watchers.isEmpty else { continue }
      activeJob = job
      currentHash = job.track.contentHash
      task = Task(priority: .utility) { @MainActor [weak self, weak job] in
        guard let self, let job else { return }
        await self.run(job)
      }
      return
    }

    activeJob = nil
    currentHash = nil
    updateActivity()
  }

  private func notifyProgress(_ job: Job, _ message: String, _ percent: Int?) {
    guard pending[job.track.contentHash] === job else { return }
    if let last = job.lastProgress, last.message == message, last.percent == percent { return }
    job.lastProgress = (message, percent)
    for watcher in Array(job.watchers.values) {
      watcher.progress(message, percent)
    }
  }

  private func finish(_ job: Job, result: Result<URL, Error>) {
    let hash = job.track.contentHash
    var callbacks: [Watcher] = []
    if pending[hash] === job {
      pending.removeValue(forKey: hash)
      callbacks = Array(job.watchers.values)
      job.watchers.removeAll()
    }

    if activeJob === job { activeJob = nil }
    task = nil
    currentHash = nil
    updateActivity()

    for watcher in callbacks { watcher.completion(result) }
    scheduleNextAfterThermalPacing()
  }

  private func finishCancelledJob(_ job: Job) {
    // A watcher-scoped cancellation already delivered its callbacks from
    // cancel(hash:token:). Only deliver cancellation here if the task itself was
    // cancelled while the job still has live watchers (for example cancelAll).
    let hash = job.track.contentHash
    var callbacks: [Watcher] = []
    if pending[hash] === job {
      pending.removeValue(forKey: hash)
      callbacks = Array(job.watchers.values)
      job.watchers.removeAll()
    }

    if activeJob === job { activeJob = nil }
    task = nil
    currentHash = nil
    updateActivity()

    for watcher in callbacks { watcher.completion(.failure(CuelixaError.cancelled)) }
    scheduleNextAfterThermalPacing()
  }

  /// Protect sustained fanless Apple Silicon workloads without slowing the
  /// first user-requested transcription. Pacing is only inserted between
  /// consecutive queued jobs when macOS reports serious/critical heat.
  private func scheduleNextAfterThermalPacing() {
    guard !pending.isEmpty else {
      startNextIfNeeded()
      return
    }

    let processInfo = ProcessInfo.processInfo
    let delay: Duration?
    switch processInfo.thermalState {
    case .critical:
      delay = .seconds(30)
    case .serious:
      delay = .seconds(10)
    case .fair:
      // A short gap between long on-device Speech jobs gives a fanless Mac a
      // chance to settle without changing foreground single-job latency.
      delay = .seconds(2)
    case .nominal:
      // Respect the user's explicit battery-saving choice for discretionary
      // queued work. The active job is never interrupted or slowed mid-file.
      delay = processInfo.isLowPowerModeEnabled ? .seconds(5) : nil
    @unknown default:
      delay = processInfo.isLowPowerModeEnabled ? .seconds(5) : nil
    }

    guard let delay else {
      startNextIfNeeded()
      return
    }

    pacingTask?.cancel()
    pacingTask = Task(priority: .utility) { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self else { return }
      self.pacingTask = nil
      self.startNextIfNeeded()
    }
    updateActivity()
  }

  private func cancelExecutorIfNeeded() async {
    if let cancellationTask = executorCancellationTask {
      await cancellationTask.value
      executorCancellationTask = nil
      return
    }
    await executor.cancelAndWait()
  }

  private func notifyProgress(
    contentHash: String, jobID: UUID, _ message: String, _ percent: Int?
  ) {
    guard let job = pending[contentHash], job.id == jobID else { return }
    notifyProgress(job, message, percent)
  }

  private func run(_ job: Job) async {
    let track = job.track
    do {
      try Task.checkCancellation()
      if let url = cache.verifiedSRTURL(hash: track.contentHash) {
        finish(job, result: .success(url))
        return
      }
      guard FileManager.default.fileExists(atPath: track.path) else {
        throw CuelixaError.missingAudio
      }

      let source = URL(fileURLWithPath: track.path)
      let suffix = source.pathExtension.isEmpty ? "audio" : source.pathExtension
      let snapshot = stagingDirectory.appendingPathComponent(
        "\(UUID().uuidString).\(suffix)")
      defer { try? FileManager.default.removeItem(at: snapshot) }
      guard try await copyAndSHA256File(from: source, to: snapshot) == track.contentHash else {
        throw CuelixaError.audioChanged
      }
      try Task.checkCancellation()

      let jobID = job.id
      let contentHash = track.contentHash
      let cues = try await executor.transcribe(
        snapshot: snapshot, duration: track.duration
      ) { [weak self] message, percent in
        self?.notifyProgress(
          contentHash: contentHash, jobID: jobID, message, percent)
      }
      try Task.checkCancellation()
      guard pending[track.contentHash] === job, !job.watchers.isEmpty else {
        await cancelExecutorIfNeeded()
        finishCancelledJob(job)
        return
      }
      guard let url = cache.commit(hash: track.contentHash, cues: cues) else {
        throw CuelixaError.invalidTranscript
      }

      notifyProgress(job, "Ready", 100)
      finish(job, result: .success(url))
    } catch is CancellationError {
      await cancelExecutorIfNeeded()
      finishCancelledJob(job)
    } catch {
      await cancelExecutorIfNeeded()
      finish(job, result: .failure(error))
    }
  }
}

enum CuelixaError: LocalizedError, Equatable {
  case unsupportedLocale
  case invalidTranscript
  case cancelled
  case missingAudio
  case audioChanged

  var errorDescription: String? {
    switch self {
    case .unsupportedLocale: "English on-device transcription is not available on this Mac."
    case .invalidTranscript: "The generated subtitles did not pass validation."
    case .cancelled: "Cancelled"
    case .missingAudio: "The lesson file is no longer available."
    case .audioChanged: "The lesson changed after the library scan. Scan it again and retry."
    }
  }
}
