// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CryptoKit
import Darwin
import Foundation

func naturalKey(_ value: String) -> [String] {
  value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
}

func naturalLess(_ a: String, _ b: String) -> Bool {
  a.localizedStandardCompare(b) == .orderedAscending
}

func durationLabel(_ seconds: Double) -> String {
  guard seconds.isFinite else { return "0:00" }
  let x = max(0, Int(seconds.rounded(.down)))
  let h = x / 3600
  let m = (x % 3600) / 60
  let s = x % 60
  return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

func clockLabel(_ seconds: Double) -> String {
  guard seconds.isFinite else { return "00:00" }
  let x = max(0, Int(seconds.rounded(.down)))
  let h = x / 3600
  let m = (x % 3600) / 60
  let s = x % 60
  return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

func sha256File(_ url: URL) -> String? {
  guard let stream = InputStream(url: url) else { return nil }
  stream.open()
  defer { stream.close() }
  var hasher = SHA256()
  var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
  while stream.hasBytesAvailable {
    let n = stream.read(&buffer, maxLength: buffer.count)
    if n < 0 { return nil }
    if n == 0 { break }
    hasher.update(data: Data(buffer[0..<n]))
  }
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Synchronous hashing for actors that must remain non-reentrant while still
/// reacting to cancellation between bounded read chunks.
func sha256FileCheckingCancellation(_ url: URL) throws -> String {
  try Task.checkCancellation()
  let input = try FileHandle(forReadingFrom: url)
  defer { try? input.close() }
  var hasher = SHA256()
  while true {
    try Task.checkCancellation()
    guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
    hasher.update(data: data)
  }
  try Task.checkCancellation()
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Hashes a potentially large lesson file without blocking MainActor and with
/// cooperative cancellation between read chunks. The detached utility task is
/// deliberately owned and awaited by its caller; it is not fire-and-forget.
func sha256FileCancellable(_ url: URL) async throws -> String {
  let work = Task.detached(priority: .utility) {
    try sha256FileCheckingCancellation(url)
  }
  return try await withTaskCancellationHandler {
    try await work.value
  } onCancel: {
    work.cancel()
  }
}

/// Copy an audio file into stable staging while hashing it. On the normal
/// APFS home volume, FileManager creates a copy-on-write clone rather than
/// rewriting the whole lesson into the cache; the snapshot is then hashed in
/// cancellable chunks. Other file systems transparently fall back to a normal
/// copy through the same Foundation API.
func copyAndSHA256File(from source: URL, to destination: URL) async throws -> String {
  let work = Task.detached(priority: .utility) {
    try Task.checkCancellation()
    try FileManager.default.copyItem(at: source, to: destination)
    try Task.checkCancellation()

    let input = try FileHandle(forReadingFrom: destination)
    defer { try? input.close() }

    var hasher = SHA256()
    while true {
      try Task.checkCancellation()
      guard let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
      hasher.update(data: data)
    }
    try Task.checkCancellation()
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  return try await withTaskCancellationHandler {
    try await work.value
  } onCancel: {
    work.cancel()
  }
}

struct FileSignature: Equatable, Sendable {
  let size: Int64
  let mtimeNS: Int64
  let ctimeNS: Int64
}
func fileSignature(_ url: URL) -> FileSignature? {
  var st = stat()
  guard lstat(url.path, &st) == 0 else { return nil }
  #if os(macOS)
    let mt = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    let ct = Int64(st.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(st.st_ctimespec.tv_nsec)
  #else
    let mt: Int64 = 0
    let ct: Int64 = 0
  #endif
  return .init(size: Int64(st.st_size), mtimeNS: mt, ctimeNS: ct)
}

private enum DisplayTitleCleaner {
  // These are deliberately conservative. Cuelixa never renames the source file;
  // it only removes unmistakable transport/download noise from the display title.
  static let leadingDate = try? NSRegularExpression(
    pattern:
      #"^\s*(?:19|20)\d{2}[._-]?(?:0[1-9]|1[0-2])[._-]?(?:0[1-9]|[12]\d|3[01])(?:[T _.-]?\d{2}[._:-]?\d{2}(?:[._:-]?\d{2})?)?\s*[-_. ]+"#,
    options: [])
  static let leadingTimestamp = try? NSRegularExpression(
    pattern: #"^\s*\d{10,13}\s*[-_. ]+"#, options: [])
  static let uuidToken = try? NSRegularExpression(
    pattern:
      #"(?i)(?:^|[\s._-])[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(?=$|[\s._-])"#,
    options: [])
  static let longHexToken = try? NSRegularExpression(
    pattern: #"(?i)(?:^|[\s._-])[0-9a-f]{12,64}(?=$|[\s._-])"#, options: [])
  static let technicalBrackets = try? NSRegularExpression(
    pattern:
      #"(?i)\s*[\[(](?=[^\])]{1,48}[\])])(?:mp3|m4a|aac|flac|wav|ogg|opus|audio|podcast|web[-_. ]?dl|webrip|download|\d{2,4}\s?kbps|\d{2,3}\s?khz|mono|stereo)(?:[\s,._+-]+(?:mp3|m4a|aac|flac|wav|ogg|opus|audio|podcast|web[-_. ]?dl|webrip|download|\d{2,4}\s?kbps|\d{2,3}\s?khz|mono|stereo))*[\])]\s*"#,
    options: [])
  static let trailingTechnicalToken = try? NSRegularExpression(
    pattern:
      #"(?i)\s*[-_. ]+(?:mp3|m4a|aac|flac|wav|ogg|opus|\d{2,4}\s?kbps|\d{2,3}\s?khz|web[-_. ]?dl|webrip|download)\s*$"#,
    options: [])

  static func replacing(
    _ regex: NSRegularExpression?, in value: String, with template: String = " "
  ) -> String {
    guard let regex else { return value }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.stringByReplacingMatches(
      in: value, options: [], range: range, withTemplate: template)
  }
}

/// Produces a calm, human-facing title for filenames that contain obvious
/// downloader timestamps, UUIDs, hashes, or codec tags. Meaningful episode
/// numbers and years are intentionally preserved. Source files are never renamed.
func humanizedTitle(_ stem: String) -> String {
  let original = stem.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !original.isEmpty else { return stem }

  var cleaned = original
  cleaned = DisplayTitleCleaner.replacing(DisplayTitleCleaner.leadingDate, in: cleaned, with: "")
  cleaned = DisplayTitleCleaner.replacing(
    DisplayTitleCleaner.leadingTimestamp, in: cleaned, with: "")
  cleaned = DisplayTitleCleaner.replacing(DisplayTitleCleaner.uuidToken, in: cleaned)
  cleaned = DisplayTitleCleaner.replacing(DisplayTitleCleaner.longHexToken, in: cleaned)
  cleaned = DisplayTitleCleaner.replacing(DisplayTitleCleaner.technicalBrackets, in: cleaned)
  cleaned = DisplayTitleCleaner.replacing(
    DisplayTitleCleaner.trailingTechnicalToken, in: cleaned, with: "")

  cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
  if !cleaned.contains(" ") && cleaned.filter({ $0 == "-" }).count >= 2 {
    cleaned = cleaned.replacingOccurrences(of: "-", with: " ")
  }
  cleaned =
    cleaned
    .replacingOccurrences(of: #"\s+-\s+"#, with: " — ", options: .regularExpression)
    .replacingOccurrences(of: #"[.]{2,}"#, with: " ", options: .regularExpression)
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    .trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_.—")))

  // A cleanup that removes nearly everything is worse than showing the source
  // stem. Fall back rather than guessing.
  let meaningfulLetters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
  if cleaned.count < 3 || meaningfulLetters < 2 {
    cleaned = original.replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  if cleaned == cleaned.lowercased() || cleaned == cleaned.uppercased() {
    return cleaned.capitalized
  }
  return cleaned
}

func audioMetadata(_ url: URL) async -> (duration: Double, title: String?) {
  let asset = AVURLAsset(url: url)
  let duration = try? await asset.load(.duration)
  let d = duration.map { CMTimeGetSeconds($0) } ?? 0
  let metadata = (try? await asset.load(.commonMetadata)) ?? []
  var title: String?
  for item in metadata where item.commonKey?.rawValue == "title" {
    do {
      if let value = try await item.load(.stringValue) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          title = trimmed
          break
        }
      }
    } catch {
      continue
    }
  }
  return (d.isFinite && d > 0 ? d : 0, title)
}
