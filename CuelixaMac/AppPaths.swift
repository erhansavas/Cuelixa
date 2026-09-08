// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation

enum LegacyLibraryIssue: String, Sendable, Equatable {
  case symbolicLink
  case notDirectory
  case inaccessible

  var userMessage: String {
    switch self {
    case .symbolicLink:
      "The legacy ~/podcast path is a symbolic link, so Cuelixa used ~/Music/Cuelixa instead."
    case .notDirectory:
      "The legacy ~/podcast path is not a folder, so Cuelixa used ~/Music/Cuelixa instead."
    case .inaccessible:
      "The legacy ~/podcast folder is not readable and writable, so Cuelixa used ~/Music/Cuelixa instead."
    }
  }
}

/// Immutable process-wide filesystem identity. Resolving the library once avoids
/// different subsystems making different migration decisions during one launch.
struct AppDirectories: Sendable {
  let library: URL
  let legacyLibrary: URL
  let defaultLibrary: URL
  let support: URL
  let cache: URL
  let transcripts: URL
  let legacySubtitles: URL
  let staging: URL
  let database: URL
  let preferences: URL
  let log: URL
  let legacyLibraryIssue: LegacyLibraryIssue?

  var usingLegacyLibrary: Bool {
    library.standardizedFileURL == legacyLibrary.standardizedFileURL
  }

  func ensure(fileManager fm: FileManager = .default) throws {
    try fm.createDirectory(at: library, withIntermediateDirectories: true)
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: library.path, isDirectory: &isDirectory), isDirectory.boolValue,
      fm.isReadableFile(atPath: library.path), fm.isWritableFile(atPath: library.path)
    else {
      throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: library.path])
    }
    for url in [support, cache, transcripts, staging] {
      try LocalFileAccess.ensurePrivateDirectory(url)
    }
  }

  static func resolve(fileManager fm: FileManager = .default) -> AppDirectories {
    resolve(home: fm.homeDirectoryForCurrentUser, fileManager: fm)
  }

  static func isolated(root: URL) -> AppDirectories {
    let library = root.appendingPathComponent("Music/Cuelixa", isDirectory: true)
    let support = root.appendingPathComponent("Application Support/Cuelixa", isDirectory: true)
    let cache = root.appendingPathComponent("Caches/Cuelixa", isDirectory: true)
    return AppDirectories(
      library: library,
      legacyLibrary: root.appendingPathComponent("podcast", isDirectory: true),
      defaultLibrary: library, support: support, cache: cache,
      transcripts: support.appendingPathComponent("Transcripts", isDirectory: true),
      legacySubtitles: cache.appendingPathComponent("subtitles", isDirectory: true),
      staging: cache.appendingPathComponent("staging", isDirectory: true),
      database: support.appendingPathComponent("library.sqlite3"),
      preferences: support.appendingPathComponent("preferences.json"),
      log: support.appendingPathComponent("app.log"), legacyLibraryIssue: nil)
  }

  static func resolve(home: URL, fileManager fm: FileManager = .default) -> AppDirectories {
    let legacy = home.appendingPathComponent("podcast", isDirectory: true)
    let music = home.appendingPathComponent("Music", isDirectory: true)
    let defaultLibrary = music.appendingPathComponent("Cuelixa", isDirectory: true)
    let selection = validatedLegacyLibrary(legacy, fileManager: fm)
    let library = selection.valid ? legacy : defaultLibrary

    let applicationSupport = home.appendingPathComponent(
      "Library/Application Support", isDirectory: true)
    let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
    let support = applicationSupport.appendingPathComponent("Cuelixa", isDirectory: true)
    let cache = caches.appendingPathComponent("Cuelixa", isDirectory: true)
    let transcripts = support.appendingPathComponent("Transcripts", isDirectory: true)
    let legacySubtitles = cache.appendingPathComponent("subtitles", isDirectory: true)
    let staging = cache.appendingPathComponent("staging", isDirectory: true)

    return AppDirectories(
      library: library, legacyLibrary: legacy, defaultLibrary: defaultLibrary,
      support: support, cache: cache, transcripts: transcripts,
      legacySubtitles: legacySubtitles, staging: staging,
      database: support.appendingPathComponent("library.sqlite3"),
      preferences: support.appendingPathComponent("preferences.json"),
      log: support.appendingPathComponent("app.log"),
      legacyLibraryIssue: selection.issue)
  }

  private static func validatedLegacyLibrary(
    _ url: URL, fileManager fm: FileManager
  ) -> (valid: Bool, issue: LegacyLibraryIssue?) {
    var status = stat()
    guard lstat(url.path, &status) == 0 else {
      return errno == ENOENT ? (false, nil) : (false, .inaccessible)
    }
    let kind = status.st_mode & mode_t(S_IFMT)
    if kind == mode_t(S_IFLNK) { return (false, .symbolicLink) }
    guard kind == mode_t(S_IFDIR) else { return (false, .notDirectory) }
    guard fm.isReadableFile(atPath: url.path), fm.isWritableFile(atPath: url.path) else {
      return (false, .inaccessible)
    }
    return (true, nil)
  }
}

enum AppPaths {
  static let current: AppDirectories = {
    #if DEBUG
      if let root = ProcessInfo.processInfo.environment["CUELIXA_UI_TEST_ROOT"], !root.isEmpty {
        return .isolated(root: URL(fileURLWithPath: root, isDirectory: true))
      }
    #endif
    return .resolve()
  }()
}
