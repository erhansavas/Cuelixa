// SPDX-License-Identifier: Apache-2.0
import XCTest

final class CuelixaLaunchTests: XCTestCase {
  func testEmptyLibraryLaunchesAndExposesKeyboardNavigation() {
    let app = XCUIApplication()
    let root = NSTemporaryDirectory() + "/CuelixaUITests-" + UUID().uuidString
    addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }
    app.launchEnvironment["CUELIXA_UI_TEST_ROOT"] = root
    app.launch()
    XCTAssertTrue(app.windows["Cuelixa"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Your Library is Empty"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Library Actions"].exists)
    app.typeKey("s", modifierFlags: [.control, .option])
    XCTAssertTrue(app.windows["Cuelixa"].exists)
  }
}
