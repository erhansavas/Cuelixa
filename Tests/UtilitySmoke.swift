// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct UtilitySmoke {
  static func main() {
    let cases: [(String, String)] = [
      ("2026-08-20_213045_The_Daily_-_AI_and_You_[128kbps]", "The Daily — AI and You"),
      ("1724184000---How-to-Learn-Swift-6-download", "How to Learn Swift 6"),
      ("550e8400-e29b-41d4-a716-446655440000_Deep_Work_Episode_12", "Deep Work Episode 12"),
      ("0123456789abcdef_MacBook_Air_M4_Review_2026_320kbps", "MacBook Air M4 Review 2026"),
      ("Episode_12_-_1984_and_Why_It_Matters", "Episode 12 — 1984 and Why It Matters"),
    ]
    for (source, expected) in cases {
      let actual = humanizedTitle(source)
      precondition(
        actual == expected, "humanizedTitle mismatch: \(source) => \(actual), expected \(expected)")
    }
    print("TITLE_CLEANUP=PASS (\(cases.count) cases)")
  }
}
