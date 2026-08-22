// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI

@MainActor
enum CuelixaDesign {
  /// Application identity color synchronized with the approved AppIcon's
  /// dominant coral payload: exact sRGB #FF645A.
  static let identityAccent = Color(red: 1.0, green: 100.0 / 255.0, blue: 90.0 / 255.0)
  static let identityAccentNS = NSColor(
    srgbRed: 1.0, green: 100.0 / 255.0, blue: 90.0 / 255.0, alpha: 1.0)

  /// Sidebar surface matches the darker first-party macOS library/navigation
  /// treatment in Dark Aqua while remaining system-derived in light appearances.
  static let sidebarBackgroundNS = NSColor(name: nil) { appearance in
    let match = appearance.bestMatch(from: [.darkAqua, .aqua])
    if match == .darkAqua {
      return NSColor(
        srgbRed: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0, alpha: 1.0)
    }
    return .windowBackgroundColor
  }
  static let sidebarBackground = Color(nsColor: sidebarBackgroundNS)
}
