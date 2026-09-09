// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation

func naturalLess(_ a: String, _ b: String) -> Bool {
  a.localizedStandardCompare(b) == .orderedAscending
}

func durationLabel(_ seconds: Double) -> String {
  guard seconds.isFinite, seconds >= 0, let x = Int64(exactly: seconds.rounded(.down)) else {
    return "0:00"
  }
  let h = x / 3600
  let m = (x % 3600) / 60
  let s = x % 60
  return h > 0 ? String(format: "%lld:%02lld:%02lld", h, m, s) : String(format: "%lld:%02lld", m, s)
}

func clockLabel(_ seconds: Double) -> String {
  guard seconds.isFinite, seconds >= 0, let x = Int64(exactly: seconds.rounded(.down)) else {
    return "00:00"
  }
  let h = x / 3600
  let m = (x % 3600) / 60
  let s = x % 60
  return h > 0
    ? String(format: "%lld:%02lld:%02lld", h, m, s) : String(format: "%02lld:%02lld", m, s)
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
