// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct SubtitleSmoke {
  static func main() throws {
    let short = "This is a short subtitle."
    let medium =
      "This medium subtitle should remain readable and balanced without unnecessary wrapping."
    let long =
      "And I'm Neil, and don't forget, you can now watch a version of this podcast on our website at BBC Learning English.com."

    let mediumBalanced = SubtitleBalancer.balance(medium, maxLineChars: 60, maxLines: 3)
    let longBalanced = SubtitleBalancer.balance(long, maxLineChars: 58, maxLines: 2)
    precondition(mediumBalanced.split(separator: "\n", omittingEmptySubsequences: false).count <= 2)
    precondition(longBalanced.split(separator: "\n", omittingEmptySubsequences: false).count <= 2)

    let cues = [
      SubtitleCue(start: 1.0, end: 2.0, text: short),
      SubtitleCue(start: 2.5, end: 4.5, text: mediumBalanced),
      SubtitleCue(start: 5.0, end: 8.0, text: longBalanced),
    ]
    let decoded = SRT.parse(SRT.encode(cues))
    precondition(decoded == cues)
    precondition(SubtitleTimeline.activeCue(in: decoded, at: 1.5)?.text == short)
    // Gap between cues must clear subtitle state.
    precondition(SubtitleTimeline.activeCue(in: decoded, at: 2.25) == nil)
    // Cue start is inclusive.
    precondition(SubtitleTimeline.activeCue(in: decoded, at: 2.5)?.text == mediumBalanced)
    // Cue end is exclusive.
    precondition(SubtitleTimeline.activeCue(in: decoded, at: 4.5) == nil)
    precondition(SubtitleTimeline.activeCue(in: decoded, at: 8.25) == nil)

    // A valid transcript may legitimately contain one final cue. r21 rejected it.
    let single = [
      SubtitleCue(start: 0.0, end: 1.25, text: "One cue is still a valid subtitle file.")
    ]
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("cuelixa-subtitle-smoke-\(UUID().uuidString).srt")
    defer { try? FileManager.default.removeItem(at: temp) }
    try SRT.encode(single).write(to: temp, atomically: true, encoding: .utf8)
    precondition(SRT.validate(url: temp))
    precondition(SRT.parse(url: temp) == single)

    let sidecarDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("cuelixa-sidecar-smoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sidecarDirectory) }
    let audioPath = sidecarDirectory.appendingPathComponent("lesson.mp3")
    let sidecarPath = sidecarDirectory.appendingPathComponent("lesson.srt")
    try SRT.encode(single).write(to: sidecarPath, atomically: true, encoding: .utf8)
    precondition(SRT.validSidecarURL(forAudioPath: audioPath.path) == sidecarPath)

    let malformed = "1\n00:00:03,000 --> 00:00:02,000\nBackwards\n"
    precondition(SRT.parse(malformed).isEmpty)

    // Runtime and tests share one deterministic handoff rule. A newer cue wins
    // at an exact boundary and during authored overlap.
    let handoff = [
      SubtitleCue(start: 10.0, end: 12.0, text: "Old"),
      SubtitleCue(start: 12.0, end: 14.0, text: "New"),
    ]
    precondition(SubtitleTimeline.activeCue(in: handoff, at: 11.999)?.text == "Old")
    precondition(SubtitleTimeline.activeCue(in: handoff, at: 12.0)?.text == "New")
    precondition(SubtitleTimeline.activeCue(in: handoff, at: 14.0) == nil)

    let overlap = [
      SubtitleCue(start: 20.0, end: 24.0, text: "Earlier"),
      SubtitleCue(start: 22.0, end: 23.0, text: "Later"),
    ]
    precondition(SubtitleTimeline.activeCue(in: overlap, at: 22.5)?.text == "Later")
    precondition(SubtitleTimeline.activeCue(in: overlap, at: 23.5)?.text == "Earlier")

    let crlfBOM =
      "\u{feff}1\r\n00:00:00,000 --> 00:00:01,250\r\nLet&apos;s do it. Café — 你好\r\n"
    let unicodeCue = SRT.parse(crlfBOM)
    precondition(unicodeCue.count == 1)
    precondition(unicodeCue[0].text == "Let's do it. Café — 你好")

    precondition(SRT.parse("1\n00:00:01,000 --> 00:00:01,000\nZero\n").isEmpty)
    precondition(SRT.parse("1\n-00:00:01,000 --> 00:00:01,000\nNegative\n").isEmpty)
    precondition(SRT.parse("1\n00:00:nan --> 00:00:02,000\nNaN\n").isEmpty)

    let timedFragments = [
      TimedTranscriptFragment(start: 0.00, end: 0.28, text: "And"),
      TimedTranscriptFragment(start: 0.28, end: 0.54, text: "I'm"),
      TimedTranscriptFragment(start: 0.54, end: 0.83, text: "Neil,"),
      TimedTranscriptFragment(start: 0.83, end: 1.16, text: "and"),
      TimedTranscriptFragment(start: 1.16, end: 1.48, text: "don't"),
      TimedTranscriptFragment(start: 1.48, end: 1.84, text: "forget,"),
      TimedTranscriptFragment(start: 1.84, end: 2.08, text: "you"),
      TimedTranscriptFragment(start: 2.08, end: 2.32, text: "can"),
      TimedTranscriptFragment(start: 2.32, end: 2.57, text: "now"),
      TimedTranscriptFragment(start: 2.57, end: 2.91, text: "watch"),
      TimedTranscriptFragment(start: 2.91, end: 3.16, text: "a"),
      TimedTranscriptFragment(start: 3.16, end: 3.48, text: "version"),
      TimedTranscriptFragment(start: 4.60, end: 4.86, text: "Let's"),
      TimedTranscriptFragment(start: 4.86, end: 5.10, text: "do"),
      TimedTranscriptFragment(start: 5.10, end: 5.34, text: "it."),
    ]
    let segmented = SubtitleSegmenter.cues(from: timedFragments)
    precondition(segmented.count >= 2)
    precondition(segmented.allSatisfy { $0.start >= 0 && $0.end > $0.start && !$0.text.isEmpty })
    precondition(
      segmented.indices.dropFirst().allSatisfy {
        segmented[$0 - 1].end <= segmented[$0].start
      })
    precondition(segmented.contains(where: { $0.text == "Let's do it." }))
    precondition(segmented.allSatisfy { !$0.text.contains(" ,") && !$0.text.contains(" .") })

    let oversizedFragment = TimedTranscriptFragment(
      start: 10, end: 22,
      text:
        "This deliberately oversized finalized passage verifies that a Speech result is not rendered as one giant subtitle paragraph and is instead divided into readable time-coded chunks for the player overlay."
    )
    let expanded = SubtitleSegmenter.cues(from: [oversizedFragment])
    precondition(expanded.count >= 2)
    precondition(expanded.allSatisfy { $0.end > $0.start && $0.text.count <= 96 })

    print("SUBTITLE_PARSE_BALANCE=PASS")
    print("SINGLE_CUE_VALIDATION=PASS")
    print("SIDECAR_SRT_COMPATIBILITY=PASS")
    print("CUE_GAP_AND_BOUNDARY=PASS")
    print("UNICODE_CRLF_BOM=PASS")
    // Starting/resuming inside a cue must resolve immediately; runtime now
    // applies this before the first AVPlayer periodic callback.
    precondition(SubtitleTimeline.activeCue(in: decoded, at: 5.75)?.text == longBalanced)

    print("SHARED_TIMELINE_HANDOFF=PASS")
    print("RESUME_CUE_RESOLUTION=PASS")
    print("TIMED_SEGMENTATION=PASS")
  }
}
