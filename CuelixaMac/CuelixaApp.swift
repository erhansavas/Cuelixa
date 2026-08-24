// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI

@main
@MainActor
struct CuelixaApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Window("Cuelixa", id: "library") {
      MainView()
        .environmentObject(appDelegate.model)
        .frame(minWidth: 760, minHeight: 520)
    }
    .defaultSize(width: 1040, height: 700)
    .windowToolbarStyle(.unified)
    .commands {
      CuelixaCommands(model: appDelegate.model)
    }
  }
}

/// Process lifecycle only. SwiftUI owns the library window's titlebar, toolbar,
/// split view and content geometry. Active playback uses a lightweight, movable,
/// nonactivating subtitle/transport overlay; the overlay owns no AVPlayer state.
/// Window chrome is never mutated from SwiftUI/AppKit view-layout callbacks;
/// lifecycle-only window properties are applied from the application delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    model.start()
    HotKeyManager.shared.install(model: model)
    NSApp.activate()

    // Give SwiftUI one event-loop turn to create the Window scene, then retain a
    // weak model reference to it for sheets/player handoff. No styleMask,
    // titlebar, toolbar or layout mutation occurs here.
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.captureLibraryWindowIfAvailable()
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    captureLibraryWindowIfAvailable()
  }

  private func captureLibraryWindowIfAvailable() {
    guard let window = model.resolveMainWindow() else { return }
    // These lifetime/organization properties don't alter the titlebar or force a
    // layout pass. Keep a closed SwiftUI-created library window available for the
    // existing Show Library/reopen workflow.
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    model.updateMainWindowInteraction()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    model.handleTerminationRequest()
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    HotKeyManager.shared.uninstall()
    model.saveNow()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    captureLibraryWindowIfAvailable()
    model.showLibraryWindow()
    return true
  }
}

@MainActor
private struct CuelixaCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandMenu("Library") {
      Button("Show Library") { model.showLibraryWindow() }
        .keyboardShortcut("s", modifiers: [.control, .option])
      Divider()
      Button("Open Library Folder") { model.openLibraryFolder() }
      Button("Prepare All Subtitles") { model.prepareAll() }
        .disabled(model.missingSubtitleCount == 0 || model.batch.active)
    }

    CommandMenu("Playback") {
      Button("Play / Pause") { model.player.togglePlayPause() }
        .keyboardShortcut("p", modifiers: [.control, .option])
      Divider()
      Button("Back 10 Seconds") { model.player.seekRelative(-10) }
        .keyboardShortcut("j", modifiers: [.control, .option])
      Button("Forward 10 Seconds") { model.player.seekRelative(10) }
        .keyboardShortcut("l", modifiers: [.control, .option])
      Button("Back 30 Seconds") { model.player.seekRelative(-30) }
        .keyboardShortcut("u", modifiers: [.control, .option])
      Button("Forward 30 Seconds") { model.player.seekRelative(30) }
        .keyboardShortcut("o", modifiers: [.control, .option])
      Button("Stop Playback") { model.stopPlayback(showLibrary: true) }
        .keyboardShortcut("q", modifiers: [.control, .option])
      Divider()
      Button(model.subtitleOverlayEnabled ? "Hide Player Overlay" : "Show Player Overlay") {
        model.toggleSubtitleOverlay()
      }
    }
  }
}
