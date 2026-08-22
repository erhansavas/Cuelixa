// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Compile-only Swift 6 regression smoke for NativeTranscriber's ownership
/// pattern. Mutable Job reference state stays MainActor-isolated while an
/// async-let child receives only Sendable identity/value data and a MainActor-
/// isolated Sendable callback.
@MainActor
private final class TranscriptionConcurrencySmokeOwner {
  private final class Job {
    let id = UUID()
    var progress = 0
  }

  private var currentJob: Job?

  private func publish(jobID: UUID, percent: Int) {
    guard let job = currentJob, job.id == jobID else { return }
    job.progress = percent
  }

  @concurrent
  private static func consume(
    jobID: UUID, progress: @escaping @MainActor @Sendable (UUID, Int) -> Void
  ) async -> Int {
    await progress(jobID, 50)
    return 1
  }

  func exercise() async {
    let job = Job()
    currentJob = job
    let jobID = job.id

    async let result = Self.consume(jobID: jobID) { [weak self] callbackJobID, percent in
      self?.publish(jobID: callbackJobID, percent: percent)
    }

    // Deliberately use mutable Job state after starting the child. This remains
    // legal because Job itself was never sent into the child concurrency region.
    job.progress += 1
    _ = await result
  }
}

@MainActor
func cuelixaTranscriptionConcurrencySmoke() async {
  let owner = TranscriptionConcurrencySmokeOwner()
  await owner.exercise()
}
