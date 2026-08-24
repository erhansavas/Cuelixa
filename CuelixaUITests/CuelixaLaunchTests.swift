// SPDX-License-Identifier: Apache-2.0
import XCTest

@MainActor
final class CuelixaLaunchTests: XCTestCase {
  func testEmptyLibraryLaunchesAndExposesKeyboardNavigation() {
    let app = XCUIApplication()
    let root = NSTemporaryDirectory() + "/CuelixaUITests-" + UUID().uuidString
    addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }
    app.launchEnvironment["CUELIXA_UI_TEST_ROOT"] = root
    app.launch()
    let libraryWindowLaunched = app.windows["Cuelixa"].waitForExistence(timeout: 8)
    let emptyStateVisible = app.staticTexts["Your Library is Empty"].waitForExistence(timeout: 5)
    let libraryActionsAccessible = app.buttons["Library Actions"].exists
    XCTAssertTrue(libraryWindowLaunched)
    XCTAssertTrue(emptyStateVisible)
    XCTAssertTrue(libraryActionsAccessible)
    app.typeKey("s", modifierFlags: [.control, .option])
    let keyboardCommandPreservedWindow = app.windows["Cuelixa"].exists
    XCTAssertTrue(keyboardCommandPreservedWindow)
  }
}
