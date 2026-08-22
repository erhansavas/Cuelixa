// SPDX-License-Identifier: Apache-2.0
import Foundation

enum AppPaths {
  /// New installs use the standard user Music directory. Existing `~/podcast`
  /// libraries remain in place and are selected non-destructively when the new
  /// default has not yet been created.
  static let legacyLibrary: URL = {
    let fm = FileManager.default
    return fm.homeDirectoryForCurrentUser.appendingPathComponent(
      "podcast", isDirectory: true)
  }()

  static let defaultLibrary: URL = {
    let fm = FileManager.default
    let music =
      fm.urls(for: .musicDirectory, in: .userDomainMask).first
      ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
    return music.appendingPathComponent("Cuelixa", isDirectory: true)
  }()

  static let library: URL = {
    let fm = FileManager.default
    // Preserve an existing legacy library for this process. Cuelixa intentionally
    // does not move or delete user media; a clean install has no legacy folder
    // and therefore starts in ~/Music/Cuelixa.
    if fm.fileExists(atPath: legacyLibrary.path) { return legacyLibrary }
    return defaultLibrary
  }()

  static let support: URL = {
    let fm = FileManager.default
    let base =
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support", isDirectory: true)
    return base.appendingPathComponent("Cuelixa", isDirectory: true)
  }()

  static let cache: URL = {
    let fm = FileManager.default
    let base =
      fm.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Caches", isDirectory: true)
    return base.appendingPathComponent("Cuelixa", isDirectory: true)
  }()

  /// Final subtitle output is expensive user-derived state, not disposable cache data.
  /// New durable transcripts therefore publish under Application Support. The r20/r21
  /// cache location remains readable through TranscriptCache so existing work is not lost.
  static let transcripts = support.appendingPathComponent("Transcripts", isDirectory: true)
  static let legacySubtitles = cache.appendingPathComponent("subtitles", isDirectory: true)
  static let staging = cache.appendingPathComponent("staging", isDirectory: true)
  static let database = support.appendingPathComponent("library.sqlite3")
  static let preferences = support.appendingPathComponent("preferences.json")
  static let log = support.appendingPathComponent("app.log")

  static var usingLegacyLibrary: Bool {
    library.standardizedFileURL == legacyLibrary.standardizedFileURL
  }

  static func ensure() throws {
    let fm = FileManager.default
    for url in [library, support, cache, transcripts, staging] {
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }
}
