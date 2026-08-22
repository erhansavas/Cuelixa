// SPDX-License-Identifier: Apache-2.0
import Foundation

enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
  case all, `continue`, upNext, completed
  var id: String { rawValue }
  var title: String {
    switch self {
    case .all: "All Lessons"
    case .continue: "Continue"
    case .upNext: "Up Next"
    case .completed: "Completed"
    }
  }
  var symbol: String {
    switch self {
    case .all: "list.bullet"
    case .continue: "clock"
    case .upNext: "chevron.right"
    case .completed: "checkmark"
    }
  }
}

struct Track: Identifiable, Hashable, Sendable {
  let contentHash: String
  var title: String
  var duration: Double
  var position: Double
  var completed: Bool
  var completedAt: Double?
  var lastPlayedAt: Double?
  var addedAt: Double
  var lastSeenAt: Double
  var missing: Bool
  var path: String
  var id: String { contentHash }
}

enum PlaybackResumePolicy {
  /// Avoids restoring into the final sliver of an item, where playback can appear to do nothing
  /// before immediately reaching end-of-item. The threshold is 2% of duration, bounded to 1...5 s.
  static func normalizedPosition(_ requested: Double, duration: Double) -> Double {
    guard requested.isFinite, requested > 0, duration.isFinite, duration > 0 else { return 0 }
    let clamped = min(requested, duration)
    if duration - clamped <= finalThreshold(for: duration) {
      return 0
    }
    return clamped
  }

  static func finalThreshold(for duration: Double) -> Double {
    guard duration.isFinite, duration > 0 else { return 1 }
    return min(5.0, max(1.0, duration * 0.02))
  }
}

struct LibraryCounts: Equatable, Sendable {
  var all = 0
  var `continue` = 0
  var upNext = 0
  var completed = 0
  subscript(_ s: LibrarySection) -> Int {
    switch s {
    case .all: all
    case .continue: `continue`
    case .upNext: upNext
    case .completed: completed
    }
  }
}

struct BatchPresentation: Equatable {
  var visible = false
  var cancelled = false
  var cancelling = false
  var active = false
  var title = "Preparing subtitles"
  var count = ""
  var track = ""
  var detail = ""
  var progress: Double? = nil
}

struct PreparationPresentation: Equatable, Identifiable {
  let id = UUID()
  let hash: String
  let title: String
  var status = "Checking local cache…"
  var percent: Int? = nil
  var failed = false
  var error = ""
}
