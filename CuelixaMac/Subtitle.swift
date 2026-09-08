// SPDX-License-Identifier: Apache-2.0
import Foundation

struct SubtitleCue: Hashable, Sendable {
  let start: Double
  let end: Double
  let text: String
}

/// One time-coded text fragment produced by SpeechTranscriber's
/// `.audioTimeRange` attributed-string runs. Keeping segmentation independent of
/// Speech/AVFoundation makes the subtitle-shaping policy deterministic and unit
/// testable.
struct TimedTranscriptFragment: Hashable, Sendable {
  let start: Double
  let end: Double
  let text: String
}

/// Converts word/phrase timing runs into readable subtitle-sized cues. Apple
/// Speech can finalize a phrase or passage that is much longer than a useful
/// on-screen subtitle. Cuelixa therefore groups time-coded runs by sentence,
/// silence, duration and visual length instead of treating each Speech result as
/// one giant SRT cue.
enum SubtitleSegmenter {
  static func cues(
    from rawFragments: [TimedTranscriptFragment],
    maxCharacters: Int = 88,
    maxDuration: Double = 6.5,
    gapThreshold: Double = 0.85
  ) -> [SubtitleCue] {
    guard maxCharacters >= 24, maxDuration > 0, gapThreshold >= 0 else { return [] }

    let fragments =
      rawFragments
      .filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }
      .flatMap { expand($0, maxCharacters: maxCharacters) }
      .sorted {
        if $0.start == $1.start { return $0.end < $1.end }
        return $0.start < $1.start
      }

    var output: [SubtitleCue] = []
    var currentText = ""
    var currentStart = 0.0
    var currentEnd = 0.0

    func flush() {
      let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty, currentEnd > currentStart {
        output.append(SubtitleCue(start: currentStart, end: currentEnd, text: text))
      }
      currentText = ""
      currentStart = 0
      currentEnd = 0
    }

    for fragment in fragments {
      let text = normalize(fragment.text)
      guard !text.isEmpty else { continue }

      if currentText.isEmpty {
        currentText = text
        currentStart = fragment.start
        currentEnd = fragment.end
      } else {
        let joined = joinedText(currentText, text)
        let gap = fragment.start - currentEnd
        let projectedDuration = fragment.end - currentStart
        let breakForGap = gap >= gapThreshold
        let breakForLength = joined.count > maxCharacters && currentText.count >= 24
        let breakForDuration = projectedDuration > maxDuration && currentText.count >= 24

        if breakForGap || breakForLength || breakForDuration {
          flush()
          currentText = text
          currentStart = fragment.start
          currentEnd = fragment.end
        } else {
          currentText = joined
          currentEnd = max(currentEnd, fragment.end)
        }
      }

      // Natural sentence boundaries are preferred once there is enough content
      // to avoid rapid one- or two-word subtitle flashes.
      let duration = currentEnd - currentStart
      if currentText.count >= 30, duration >= 1.0, endsSentence(currentText) {
        flush()
      }
    }
    flush()

    // Guarantee a monotonic, valid SRT timeline. A small overlap may be authored
    // by Speech timing runs; clipping only the previous end avoids ambiguous
    // simultaneous generated cues without changing source-owned sidecar SRTs.
    guard output.count > 1 else { return output }
    var normalized: [SubtitleCue] = []
    normalized.reserveCapacity(output.count)
    for cue in output {
      if let previous = normalized.last, previous.end > cue.start {
        normalized.removeLast()
        let clippedEnd = max(previous.start + 0.05, cue.start)
        if clippedEnd > previous.start {
          normalized.append(
            SubtitleCue(start: previous.start, end: clippedEnd, text: previous.text))
        }
      }
      normalized.append(cue)
    }
    return normalized
  }

  private static func expand(
    _ fragment: TimedTranscriptFragment, maxCharacters: Int
  ) -> [TimedTranscriptFragment] {
    let text = normalize(fragment.text)
    guard text.count > maxCharacters else {
      return [TimedTranscriptFragment(start: fragment.start, end: fragment.end, text: text)]
    }

    let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard words.count > 1 else {
      return [TimedTranscriptFragment(start: fragment.start, end: fragment.end, text: text)]
    }

    var chunks: [String] = []
    var current = ""
    for word in words {
      let candidate = current.isEmpty ? word : current + " " + word
      if !current.isEmpty, candidate.count > maxCharacters {
        chunks.append(current)
        current = word
      } else {
        current = candidate
      }
      if current.count >= maxCharacters * 2 / 3, endsSentence(current) {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty { chunks.append(current) }
    guard chunks.count > 1 else {
      return [TimedTranscriptFragment(start: fragment.start, end: fragment.end, text: text)]
    }

    let totalWeight = max(1, chunks.reduce(0) { $0 + max(1, $1.count) })
    let duration = fragment.end - fragment.start
    var elapsedWeight = 0
    return chunks.enumerated().map { index, chunk in
      let startFraction = Double(elapsedWeight) / Double(totalWeight)
      elapsedWeight += max(1, chunk.count)
      let endFraction =
        index == chunks.count - 1 ? 1.0 : Double(elapsedWeight) / Double(totalWeight)
      return TimedTranscriptFragment(
        start: fragment.start + duration * startFraction,
        end: fragment.start + duration * endFraction,
        text: chunk)
    }
  }

  private static func normalize(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  private static func joinedText(_ lhs: String, _ rhs: String) -> String {
    guard let first = rhs.first else { return lhs }
    let noLeadingSpace = ".,!?;:%)]}’'".contains(first)
    let noTrailingSpace = lhs.last.map { "([{‘'".contains($0) } ?? false
    return noLeadingSpace || noTrailingSpace ? lhs + rhs : lhs + " " + rhs
  }

  private static func endsSentence(_ value: String) -> Bool {
    guard let last = value.last else { return false }
    return ".!?…".contains(last)
  }
}

/// Shared subtitle timing semantics used by both deterministic tests and the
/// live player. Cues are active on a half-open interval [start, end). At an
/// authored overlap, the most recently started cue wins. This makes an exact
/// handoff deterministic: when one cue ends exactly as the next starts, the
/// new cue is displayed immediately rather than briefly retaining old text.
enum SubtitleTimeline {
  static func prefixMaximumEnds(for cues: [SubtitleCue]) -> [Double] {
    var maximum = -Double.infinity
    return cues.map { cue in
      maximum = max(maximum, cue.end)
      return maximum
    }
  }

  static func activeCueIndex(
    in cues: [SubtitleCue], prefixMaximumEnds: [Double], at time: Double
  ) -> Int? {
    guard time.isFinite, !cues.isEmpty, prefixMaximumEnds.count == cues.count else { return nil }

    // Find the newest cue that has started.
    var low = 0
    var high = cues.count
    while low < high {
      let middle = low + (high - low) / 2
      if cues[middle].start <= time {
        low = middle + 1
      } else {
        high = middle
      }
    }
    let lastStarted = low - 1
    guard lastStarted >= 0, prefixMaximumEnds[lastStarted] > time else { return nil }

    // Find the earliest index that could still overlap this timestamp. The
    // backwards scan then returns the newest active cue without walking old
    // transcript history during ordinary gaps.
    low = 0
    high = lastStarted + 1
    while low < high {
      let middle = low + (high - low) / 2
      if prefixMaximumEnds[middle] > time {
        high = middle
      } else {
        low = middle + 1
      }
    }

    var index = lastStarted
    while index >= low {
      let cue = cues[index]
      if cue.start <= time && time < cue.end { return index }
      index -= 1
    }
    return nil
  }

  static func activeCue(in cues: [SubtitleCue], at time: Double) -> SubtitleCue? {
    let prefix = prefixMaximumEnds(for: cues)
    return activeCueIndex(in: cues, prefixMaximumEnds: prefix, at: time).map { cues[$0] }
  }
}

enum SRT {
  // Far above ordinary lesson transcripts, but bounded before allocating or
  // parsing an untrusted sidecar (including a file that grows during reading).
  static let maximumFileBytes = 16 * 1_024 * 1_024

  static func validSidecarURL(forAudioPath path: String) -> URL? {
    let audioURL = URL(fileURLWithPath: path)
    let sidecar = audioURL.deletingPathExtension().appendingPathExtension("srt")
    return validate(url: sidecar) ? sidecar : nil
  }

  static func parse(url: URL) -> [SubtitleCue] {
    guard let data = try? LocalFileAccess.readData(at: url, maximumBytes: maximumFileBytes),
      let source = String(data: data, encoding: .utf8)
    else { return [] }
    return parse(source)
  }

  static func parse(_ source: String) -> [SubtitleCue] {
    guard source.utf8.count <= maximumFileBytes else { return [] }
    let normalized =
      source
      .replacingOccurrences(of: "\u{feff}", with: "")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let separated = normalized.replacingOccurrences(
      of: #"\n[\t ]*\n"#, with: "\n\n", options: .regularExpression)
    return separated.components(separatedBy: "\n\n").compactMap { block in
      let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard lines.count >= 2 else { return nil }
      let timingIndex = lines[0].contains("-->") ? 0 : 1
      guard lines.indices.contains(timingIndex) else { return nil }
      let parts = lines[timingIndex].components(separatedBy: "-->")
      guard parts.count == 2, let start = time(parts[0]), let end = time(parts[1]),
        start.isFinite, end.isFinite, start >= 0, end > start
      else { return nil }
      let text = displayText(
        lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(
          in: .whitespacesAndNewlines))
      return text.isEmpty ? nil : SubtitleCue(start: start, end: end, text: text)
    }.sorted { $0.start < $1.start }
  }

  static func validate(url: URL) -> Bool {
    !parse(url: url).isEmpty
  }

  static func encode(_ cues: [SubtitleCue]) -> String {
    guard
      cues.allSatisfy({
        milliseconds($0.start) != nil && milliseconds($0.end) != nil && $0.end > $0.start
      })
    else { return "" }
    return cues.enumerated().map { index, cue in
      "\(index + 1)\n\(stamp(cue.start)) --> \(stamp(cue.end))\n\(cue.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }.joined(separator: "\n")
  }

  private static func time(_ value: String) -> Double? {
    let timestamp =
      value.trimmingCharacters(in: .whitespaces)
      .split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
    guard !timestamp.hasPrefix("-") else { return nil }
    let parts = timestamp.replacingOccurrences(of: ",", with: ".")
      .split(separator: ":")
    guard parts.count == 3,
      let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]),
      hours.isFinite, minutes.isFinite, seconds.isFinite,
      hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60
    else { return nil }
    return hours * 3600 + minutes * 60 + seconds
  }

  private static func stamp(_ value: Double) -> String {
    guard let ms = milliseconds(value) else { return "00:00:00,000" }
    let hours = ms / 3_600_000
    let minutes = (ms % 3_600_000) / 60_000
    let seconds = (ms % 60_000) / 1000
    let remainder = ms % 1000
    return String(format: "%02lld:%02lld:%02lld,%03lld", hours, minutes, seconds, remainder)
  }

  private static func milliseconds(_ value: Double) -> Int64? {
    guard value.isFinite, value >= 0 else { return nil }
    return Int64(exactly: (value * 1000).rounded())
  }

  /// AVPlayer does not parse external SRT payloads for the custom subtitle
  /// overlay. Normalize the presentation subset that mpv decoded for the
  /// accepted Cuelixa subtitle presentation while preserving authored line breaks.
  private static func displayText(_ value: String) -> String {
    var text = value.replacingOccurrences(
      of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(
      of: #"(?i)</?(?:b|i|u|s|font)(?:\s+[^>]*)?>"#, with: "",
      options: .regularExpression)
    text = text.replacingOccurrences(
      of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)

    var result = ""
    var cursor = text.startIndex
    while cursor < text.endIndex {
      guard let ampersand = text[cursor...].firstIndex(of: "&") else {
        result.append(contentsOf: text[cursor...])
        cursor = text.endIndex
        break
      }
      result.append(contentsOf: text[cursor..<ampersand])
      let entityEnd = text.index(ampersand, offsetBy: 13, limitedBy: text.endIndex) ?? text.endIndex
      guard let semicolon = text[ampersand..<entityEnd].firstIndex(of: ";")
      else {
        result.append("&")
        cursor = text.index(after: ampersand)
        continue
      }
      let entity = String(text[text.index(after: ampersand)..<semicolon])
      if let decoded = decodeEntity(entity) {
        result.append(contentsOf: decoded)
        cursor = text.index(after: semicolon)
      } else {
        result.append("&")
        cursor = text.index(after: ampersand)
      }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func decodeEntity(_ entity: String) -> String? {
    switch entity.lowercased() {
    case "amp": return "&"
    case "lt": return "<"
    case "gt": return ">"
    case "quot": return "\""
    case "apos", "#39": return "'"
    case "nbsp": return "\u{00a0}"
    default: break
    }

    let number: UInt32?
    if entity.lowercased().hasPrefix("#x") {
      number = UInt32(entity.dropFirst(2), radix: 16)
    } else if entity.hasPrefix("#") {
      number = UInt32(entity.dropFirst(), radix: 10)
    } else {
      number = nil
    }
    guard let number, let scalar = UnicodeScalar(number) else { return nil }
    return String(Character(scalar))
  }
}

enum SubtitleBalancer {
  private static let weakEnds: Set<String> = [
    "a", "an", "the", "to", "of", "in", "on", "at", "for", "from", "with", "and", "or", "but", "if",
    "as", "by",
  ]
  private static let breakStarts: Set<String> = [
    "and", "but", "or", "so", "because", "while", "when", "if", "although", "though", "yet",
  ]

  static func balance(_ raw: String, maxLineChars: Int = 58, maxLines: Int = 3) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let authored = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
      .map { collapse(String($0)) }
      .filter { !$0.isEmpty }
    if authored.count > 1
      && authored.contains(where: { $0.hasPrefix("-") || $0.hasPrefix("–") || $0.hasPrefix("—") })
    {
      return authored.joined(separator: "\n")
    }

    let text = collapse(trimmed)
    guard maxLineChars > 0, maxLines > 0 else { return text }
    guard text.count > maxLineChars else { return text }
    let words = text.split(separator: " ").map(String.init)
    guard words.count >= 6 else { return text }

    var lineCount = min(
      maxLines, max(2, Int(ceil(Double(text.count) / (Double(maxLineChars) * 1.02)))))
    lineCount = min(lineCount, max(1, words.count / 2))
    guard lineCount >= 2 else { return text }

    // Keep the exact scoring for normal cues. Large user-authored paragraphs
    // use a linear partition that preserves every word, instead of searching
    // a combinatorial number of possible line breaks on the playback actor.
    if words.count > 256 || lineCount > 3 {
      return partitionLongCue(words, lineCount: lineCount)
    }

    let target = Double(text.count) / Double(lineCount)
    var bestScore: Double?
    var bestSplits: [Int]?
    var prefixLengths = [0]
    for word in words { prefixLengths.append((prefixLengths.last ?? 0) + word.count + 1) }
    let weakEnd = words.map { weakEnds.contains(stripTrailingPunctuation($0.lowercased())) }
    let breakStart = words.map { breakStarts.contains(stripLeadingPunctuation($0.lowercased())) }
    let punctuatedEnd = words.map { word in
      word.last.map { ",;:.!?".contains($0) } ?? false
    }

    func evaluate(_ splits: [Int]) {
      let starts = [0] + splits
      let ends = splits + [words.count]
      var lengths: [Int] = []
      for index in starts.indices {
        let start = starts[index]
        let end = ends[index]
        guard end - start >= 2 else { return }
        lengths.append(prefixLengths[end] - prefixLengths[start] - 1)
      }
      var score = lengths.reduce(0.0) { $0 + pow(Double($1) - target, 2) }
      score += lengths.reduce(0.0) { total, length in
        total + pow(max(0.0, Double(length - maxLineChars)), 2) * 12
      }
      score += lengths.reduce(0.0) { total, length in
        total + pow(max(0.0, target * 0.55 - Double(length)), 2) * 3
      }

      for split in splits {
        if weakEnd[split - 1] { score += 55 }
        if punctuatedEnd[split - 1] { score -= 6 }
        if breakStart[split] { score -= 5 }
      }
      if words.count - (splits.last ?? 0) <= 2 { score += 120 }

      if let currentBest = bestScore {
        if score < currentBest {
          bestScore = score
          bestSplits = splits
        }
      } else {
        bestScore = score
        bestSplits = splits
      }
    }

    func choose(_ next: Int, _ remaining: Int, _ cuts: inout [Int]) {
      if remaining == 0 {
        evaluate(cuts)
        return
      }
      let maxCandidate = words.count - 2
      guard next <= maxCandidate else { return }
      for candidate in next...maxCandidate {
        if words.count - candidate < remaining * 2 { break }
        cuts.append(candidate)
        choose(candidate + 2, remaining - 1, &cuts)
        cuts.removeLast()
      }
    }

    var cuts: [Int] = []
    choose(2, lineCount - 1, &cuts)
    guard let bestSplits else { return text }
    return zip([0] + bestSplits, bestSplits + [words.count])
      .map { words[$0..<$1].joined(separator: " ") }.joined(separator: "\n")
  }

  private static func partitionLongCue(_ words: [String], lineCount: Int) -> String {
    let lengths = words.map { $0.count + 1 }
    var remainingLength = lengths.reduce(0, +)
    var next = 0
    var lines: [String] = []
    for line in 0..<lineCount {
      let remainingLines = lineCount - line
      if remainingLines == 1 {
        lines.append(words[next...].joined(separator: " "))
        break
      }
      let target = remainingLength / remainingLines
      let start = next
      var length = 0
      let lastAllowed = words.count - (remainingLines - 1) * 2
      while next < lastAllowed && (next - start < 2 || length < target) {
        length += lengths[next]
        next += 1
      }
      remainingLength -= length
      lines.append(words[start..<next].joined(separator: " "))
    }
    return lines.joined(separator: "\n")
  }

  private static func collapse(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  private static func stripTrailingPunctuation(_ value: String) -> String {
    var scalars = Array(value.unicodeScalars)
    while let last = scalars.last, !CharacterSet.alphanumerics.contains(last) && last != "'" {
      scalars.removeLast()
    }
    return String(String.UnicodeScalarView(scalars))
  }

  private static func stripLeadingPunctuation(_ value: String) -> String {
    var scalars = Array(value.unicodeScalars)
    while let first = scalars.first, !CharacterSet.alphanumerics.contains(first) && first != "'" {
      scalars.removeFirst()
    }
    return String(String.UnicodeScalarView(scalars))
  }
}
