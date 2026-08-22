// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
struct AttributedStringRunSmoke {
  static func main() {
    let attributed = AttributedString("Hello timed world")
    var rebuilt = ""
    var runCount = 0

    // Foundation.AttributedString.Runs.Element is a Run, not a (range, run) tuple.
    // This executable prevents the Xcode 26.6 AttributedString-runs regression
    // from being reintroduced by a source-only review.
    for run in attributed.runs {
      runCount += 1
      rebuilt += String(attributed[run.range].characters)
    }

    precondition(runCount > 0)
    precondition(rebuilt == "Hello timed world")
    print("ATTRIBUTED_STRING_RUN_API=PASS")
  }
}
