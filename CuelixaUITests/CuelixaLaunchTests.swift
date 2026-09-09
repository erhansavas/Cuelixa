// SPDX-License-Identifier: Apache-2.0
import XCTest

@MainActor
final class CuelixaLaunchTests: XCTestCase {
  func testEmptyLibraryLaunchesAndAcceptsKeyboardCommand() throws {
    let root = try isolatedRoot()
    let app = launch(root: root)
    XCTAssertTrue(app.staticTexts["Your Library is Empty"].waitForExistence(timeout: 10))
    assertIsolatedDatabase(root: root)

    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 5))
    app.typeKey("s", modifierFlags: [.control, .option])
    XCTAssertTrue(app.staticTexts["Your Library is Empty"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.windows.count, 1)
  }

  func testSearchCompletionAndRelaunchPreserveLibraryState() throws {
    let root = try isolatedRoot()
    try writeSilentLesson("Café Lesson", seconds: 60, root: root)
    try writeSilentLesson("Second Lesson", seconds: 61, root: root)
    let app = launch(root: root)
    assertIsolatedDatabase(root: root)
    let lesson = app.staticTexts["Café Lesson"]
    XCTAssertTrue(lesson.waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Second Lesson"].exists)

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.exists)
    search.click()
    search.typeText("cafe lesson")
    XCTAssertEqual(search.value as? String, "cafe lesson")
    XCTAssertTrue(lesson.exists)
    XCTAssertTrue(app.staticTexts["Second Lesson"].waitForNonExistence(timeout: 5))
    search.typeKey("a", modifierFlags: .command)
    search.typeKey(.delete, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["Second Lesson"].waitForExistence(timeout: 5))

    lesson.rightClick()
    app.menuItems["Mark as Finished"].click()
    XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
    app.outlines["Sidebar"].staticTexts.matching(
      NSPredicate(format: "value == %@", "Completed, 1")
    ).firstMatch.click()
    XCTAssertTrue(app.staticTexts["Second Lesson"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(lesson.exists)
    app.terminate()
    app.launch()
    XCTAssertTrue(lesson.waitForExistence(timeout: 15))
    lesson.rightClick()
    XCTAssertTrue(app.menuItems["Mark as Unfinished"].waitForExistence(timeout: 5))
    app.typeKey(.escape, modifierFlags: [])
  }

  func testSidecarPlaybackAndKeyboardStopReturnToLibrary() throws {
    let root = try isolatedRoot()
    try writeSilentLesson("Playback Lesson", seconds: 60, root: root)
    let sidecar = root.appendingPathComponent("Music/Cuelixa/Playback Lesson.srt")
    try "1\n00:00:00,000 --> 00:01:00,000\nCuelixa UI subtitle fixture.\n".write(
      to: sidecar, atomically: true, encoding: .utf8)
    let app = launch(root: root)
    assertIsolatedDatabase(root: root)
    let play = app.buttons["Play Playback Lesson"]
    XCTAssertTrue(play.waitForExistence(timeout: 15))
    app.staticTexts["Playback Lesson"].click()
    app.typeKey(.space, modifierFlags: [])
    XCTAssertTrue(
      app.staticTexts["Cuelixa UI subtitle fixture."].waitForExistence(timeout: 15),
      app.debugDescription)
    try auditAccessibility(app)
    let screenshot = XCTAttachment(
      screenshot: app.staticTexts["Cuelixa UI subtitle fixture."].screenshot())
    screenshot.name = "SubtitleOverlay"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.typeKey("q", modifierFlags: [.control, .option])
    XCTAssertTrue(play.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Cuelixa UI subtitle fixture."].waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    XCTAssertTrue(app.staticTexts["Playback Lesson"].isHittable)
    app.staticTexts["Playback Lesson"].click()
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      app.staticTexts["Cuelixa UI subtitle fixture."].waitForExistence(timeout: 15),
      app.debugDescription)
    app.typeKey("q", modifierFlags: [.control, .option])
    XCTAssertTrue(play.waitForExistence(timeout: 10))
  }

  func testLibraryAccessibilityAndResizingInLightAndDarkAppearance() throws {
    let device = XCUIDevice.shared
    let originalAppearance = device.appearance
    addTeardownBlock { @MainActor in device.appearance = originalAppearance }
    for appearance in [XCUIDevice.Appearance.light, .dark] {
      device.appearance = appearance
      let root = try isolatedRoot()
      try writeSilentLesson("Accessible Lesson", seconds: 60, root: root)
      let app = launch(root: root)
      assertIsolatedDatabase(root: root)
      let play = app.buttons["Play Accessible Lesson"]
      XCTAssertTrue(play.waitForExistence(timeout: 15))
      let window = app.windows.firstMatch
      let initialFrame = window.frame
      let compactSize = CGSize(width: 780, height: 620)

      let compactCorner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        .withOffset(CGVector(dx: -2, dy: -2))
      let compactDestination = window.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: compactSize.width - 2, dy: compactSize.height - 2))
      compactCorner.click(forDuration: 0.1, thenDragTo: compactDestination)
      let compactFrame = window.frame
      XCTAssertEqual(compactFrame.width, compactSize.width, accuracy: 5)
      XCTAssertEqual(compactFrame.height, compactSize.height, accuracy: 5)
      XCTAssertTrue(play.isHittable)
      XCTAssertTrue(app.searchFields.firstMatch.isHittable)
      try auditAccessibility(app)
      let compactScreenshot = XCTAttachment(screenshot: window.screenshot())
      compactScreenshot.name = "Library-\(appearance == .light ? "Light" : "Dark")-Compact"
      compactScreenshot.lifetime = .keepAlways
      add(compactScreenshot)

      let expandedCorner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        .withOffset(CGVector(dx: -2, dy: -2))
      let expandedDestination = window.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: initialFrame.width - 2, dy: initialFrame.height - 2))
      expandedCorner.click(forDuration: 0.1, thenDragTo: expandedDestination)
      let expandedFrame = window.frame
      XCTAssertEqual(expandedFrame.width, initialFrame.width, accuracy: 5)
      XCTAssertEqual(expandedFrame.height, initialFrame.height, accuracy: 5)
      XCTAssertGreaterThan(expandedFrame.width, compactFrame.width)
      XCTAssertGreaterThan(expandedFrame.height, compactFrame.height)
      XCTAssertTrue(play.isHittable)
      XCTAssertTrue(app.searchFields.firstMatch.isHittable)
      try auditAccessibility(app)
      let expandedScreenshot = XCTAttachment(screenshot: window.screenshot())
      expandedScreenshot.name = "Library-\(appearance == .light ? "Light" : "Dark")-Expanded"
      expandedScreenshot.lifetime = .keepAlways
      add(expandedScreenshot)
      app.terminate()
    }
  }

  private func isolatedRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("CuelixaUITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Music/Cuelixa"), withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: root) }
    return root
  }

  private func launch(root: URL) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["CUELIXA_UI_TEST_ROOT"] = root.path
    app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
    addTeardownBlock { @MainActor in app.terminate() }
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    return app
  }

  private func assertIsolatedDatabase(root: URL) {
    // A launch alone can pass even if DEBUG was omitted and the real library was used.
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("Application Support/Cuelixa/library.sqlite3").path))
  }

  private func auditAccessibility(_ app: XCUIApplication) throws {
    // Contrast and native menu-action audit limitations are recorded in the historical
    // engineering audit under docs/audits; this is not a complete VoiceOver qualification.
    try app.performAccessibilityAudit(for: [
      .elementDetection, .hitRegion, .sufficientElementDescription, .parentChild,
    ]) { issue in
      // SwiftUI exposes unnamed, noninteractive layout groups around labelled children.
      // Audit their controls normally; a container does not need a duplicate description.
      if issue.auditType == .sufficientElementDescription,
        let element = issue.element
      {
        // MediaPlayer also exposes a system Touch Bar container on Macs without a Touch Bar.
        if element.elementType == .touchBar { return true }
        if element.elementType == .group, !element.isEnabled,
          element.children(matching: .any).count > 0
        {
          return true
        }
      }
      // Include the failing native hierarchy in hosted CI logs, not just the audit category.
      print("Accessibility audit failed: \(issue.detailedDescription)")
      print(issue.element?.debugDescription ?? "No audit element")
      print(app.debugDescription)
      return false
    }
  }

  private func writeSilentLesson(_ title: String, seconds: UInt32, root: URL) throws {
    let dataByteCount = seconds * 8_000 * 2
    var wav = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      var value = value.littleEndian
      withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
    }
    wav.append(contentsOf: "RIFF".utf8)
    append(UInt32(36) + dataByteCount)
    wav.append(contentsOf: "WAVEfmt ".utf8)
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(8_000))
    append(UInt32(16_000))
    append(UInt16(2))
    append(UInt16(16))
    wav.append(contentsOf: "data".utf8)
    append(dataByteCount)
    wav.append(Data(count: Int(dataByteCount)))
    try wav.write(to: root.appendingPathComponent("Music/Cuelixa/\(title).wav"))
  }
}
