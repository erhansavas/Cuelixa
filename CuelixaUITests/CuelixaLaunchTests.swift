// SPDX-License-Identifier: Apache-2.0
import XCTest

@MainActor
final class CuelixaLaunchTests: XCTestCase {
  func testEmptyLibraryLaunchesAndAcceptsKeyboardCommand() {
    let app = XCUIApplication()
    let root = NSTemporaryDirectory() + "/CuelixaUITests-" + UUID().uuidString
    addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }
    app.launchEnvironment["CUELIXA_UI_TEST_ROOT"] = root
    app.launch()
    let reachedForeground = app.wait(for: .runningForeground, timeout: 15)
    XCTAssertTrue(reachedForeground)
    app.typeKey("s", modifierFlags: [.control, .option])
    let remainedRunning =
      app.state == .runningForeground || app.state == .runningBackground
    XCTAssertTrue(remainedRunning)
  }
}
