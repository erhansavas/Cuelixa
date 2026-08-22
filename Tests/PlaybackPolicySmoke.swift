// SPDX-License-Identifier: Apache-2.0
import Foundation

@main
enum PlaybackPolicySmoke {
  static func main() {
    precondition(PlaybackResumePolicy.normalizedPosition(0, duration: 361) == 0)
    precondition(PlaybackResumePolicy.normalizedPosition(55, duration: 354) == 55)
    precondition(PlaybackResumePolicy.normalizedPosition(359, duration: 361) == 0)
    precondition(PlaybackResumePolicy.normalizedPosition(360.9, duration: 361) == 0)
    precondition(PlaybackResumePolicy.normalizedPosition(300, duration: 361) == 300)
    precondition(PlaybackResumePolicy.normalizedPosition(999, duration: 361) == 0)
    precondition(PlaybackResumePolicy.finalThreshold(for: 20) == 1)
    precondition(PlaybackResumePolicy.finalThreshold(for: 361) == 5)
    print("PLAYBACK_RESUME_POLICY=PASS")
  }
}
