// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI

/// Content hosted inside a real AppKit sheet/window. AppKit owns the window
/// chrome, dimming, modality, focus containment, shadow and corner treatment;
/// Cuelixa supplies only the scoped task content.
private struct NativeSheetContent<Content: View>: View {
  let width: CGFloat
  let height: CGFloat
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .padding(.vertical, 20)
      .padding(.horizontal, 22)
      .frame(width: width, height: height, alignment: .topLeading)
      .foregroundStyle(.primary)
  }
}

private enum DialogButtonKind { case secondary, primary, destructive }

private struct DialogActionButton: View {
  let title: String
  let kind: DialogButtonKind
  var initialFocus = false
  let action: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    styledButton
      .focused($focused)
      .onAppear {
        guard initialFocus else { return }
        Task { @MainActor in focused = true }
      }
  }

  @ViewBuilder
  private var styledButton: some View {
    let button = Button(role: kind == .destructive ? .destructive : nil, action: action) {
      Text(title)
    }
    .controlSize(.regular)

    switch kind {
    case .primary, .destructive:
      button.buttonStyle(.borderedProminent)
    case .secondary:
      button.buttonStyle(.bordered)
    }
  }
}

private struct CuelixaProgressBar: View {
  let value: Double?

  @ViewBuilder
  var body: some View {
    if let value {
      ProgressView(value: max(0, min(1, value)))
        .progressViewStyle(.linear)
        .tint(CuelixaDesign.identityAccent)
    } else {
      ProgressView()
        .progressViewStyle(.linear)
        .controlSize(.small)
        .tint(CuelixaDesign.identityAccent)
    }
  }
}

struct MissingSubtitlesSheet: View {
  @EnvironmentObject var model: AppModel
  let track: Track

  var body: some View {
    NativeSheetContent(width: 480, height: 198) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Subtitles aren’t ready")
          .font(.headline)
        Text(track.title)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        Text("Prepare subtitles locally before playing, or start the lesson now without subtitles.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          Spacer()
          DialogActionButton(title: "Cancel", kind: .secondary) { model.dismissMissing() }
            .keyboardShortcut(.cancelAction)
          DialogActionButton(title: "Play Without Subtitles", kind: .secondary) {
            model.playWithoutSubtitles(track)
          }
          DialogActionButton(title: "Prepare & Play", kind: .primary, initialFocus: true) {
            model.prepareAndPlay(track)
          }
          .keyboardShortcut(.defaultAction)
        }
      }
    }
  }
}

struct PreparationSheet: View {
  @EnvironmentObject var model: AppModel
  let prep: PreparationPresentation

  var body: some View {
    let current = model.preparation ?? prep
    NativeSheetContent(width: 480, height: 216) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Preparing subtitles")
          .font(.headline)
        Text(current.title)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        Text(current.failed ? "Could not prepare subtitles" : normalizedStatus(current.status))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        CuelixaProgressBar(
          value: current.failed ? 0 : current.percent.map { Double($0) / 100.0 }
        )
        Text(
          current.failed
            ? current.error
            : (current.percent.map { "\($0)% · local transcription" }
              ?? "Runs locally · one transcription job at a time")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          Spacer()
          DialogActionButton(title: current.failed ? "Close" : "Cancel", kind: .secondary) {
            model.cancelSinglePreparation()
          }
          .keyboardShortcut(.cancelAction)
        }
      }
    }
  }

  private func normalizedStatus(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "preparing subtitles"
      ? "Processing audio locally…" : value
  }
}

struct CompletionSheet: View {
  @EnvironmentObject var model: AppModel
  let track: Track

  var body: some View {
    NativeSheetContent(width: 450, height: 190) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Did you finish this lesson?")
          .font(.headline)
        Text(track.title)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        Text("Finished lessons move to Completed. You can undo this later.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          Spacer()
          DialogActionButton(title: "Replay", kind: .secondary) { model.replayCurrent() }
          DialogActionButton(title: "Not Yet", kind: .secondary) {
            model.finishCurrent(completed: false)
          }
          .keyboardShortcut(.cancelAction)
          DialogActionButton(title: "Mark as Finished", kind: .primary) {
            model.finishCurrent(completed: true)
          }
          .keyboardShortcut(.defaultAction)
        }
      }
    }
  }
}

struct QuitSheet: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    NativeSheetContent(width: 458, height: 188) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Quit Cuelixa while subtitles are being prepared?")
          .font(.headline)
        Text(model.quitPreparationSummary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text(
          "Completed subtitle sets are already saved. Quitting stops only the current transcription and any queued work."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          Spacer()
          DialogActionButton(title: "Cancel", kind: .secondary, initialFocus: true) {
            model.dismissQuitWarning()
          }
          .keyboardShortcut(.cancelAction)
          DialogActionButton(title: "Quit Cuelixa", kind: .destructive) { model.confirmQuit() }
        }
      }
    }
  }
}

@MainActor
final class DialogSheetController {
  private weak var model: AppModel?
  private var missingWindow: NSWindow?
  private var preparationWindow: NSWindow?
  private var completionWindow: NSWindow?

  init(model: AppModel) { self.model = model }

  func showMissing(track: Track) {
    guard let model else { return }
    hideMissing()
    let window = makeSheet(width: 480, height: 198, title: "Subtitles")
    window.contentViewController = NSHostingController(
      rootView: MissingSubtitlesSheet(track: track).environmentObject(model))
    missingWindow = window
    present(window)
  }

  func hideMissing() {
    dismiss(missingWindow)
    missingWindow = nil
  }

  func showPreparation(_ prep: PreparationPresentation) {
    guard let model else { return }
    hidePreparation()
    let window = makeSheet(width: 480, height: 216, title: "Preparing Subtitles")
    window.contentViewController = NSHostingController(
      rootView: PreparationSheet(prep: prep).environmentObject(model))
    preparationWindow = window
    present(window)
  }

  func hidePreparation() {
    dismiss(preparationWindow)
    preparationWindow = nil
  }

  func showCompletion(track: Track) {
    guard let model else { return }
    hideCompletion()
    let window = makeSheet(width: 450, height: 190, title: "Finished")
    window.contentViewController = NSHostingController(
      rootView: CompletionSheet(track: track).environmentObject(model))
    completionWindow = window
    present(window)
  }

  func hideCompletion() {
    dismiss(completionWindow)
    completionWindow = nil
  }

  func focusActive() {
    if let completionWindow, model?.completionTrack != nil {
      present(completionWindow)
    } else if let preparationWindow, model?.preparation != nil {
      present(preparationWindow)
    } else if let missingWindow, model?.missingPrompt != nil {
      present(missingWindow)
    }
  }

  /// Temporarily ends the current sheet without destroying its hosted state.
  /// The quit flow can then present its own sheet and restore this one if quit
  /// is cancelled.
  func suspendActive() {
    if let completionWindow { dismiss(completionWindow, destroy: false) }
    if let preparationWindow { dismiss(preparationWindow, destroy: false) }
    if let missingWindow { dismiss(missingWindow, destroy: false) }
  }

  private func makeSheet(width: CGFloat, height: CGFloat, title: String) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.isMovable = false
    return window
  }

  private func present(_ window: NSWindow) {
    guard let parent = model?.resolveMainWindow() else {
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    parent.makeKeyAndOrderFront(nil)
    if window.sheetParent == nil {
      parent.beginSheet(window)
    } else {
      window.makeKey()
    }
    model?.updateMainWindowInteraction()
    NSApp.activate()
  }

  private func dismiss(_ window: NSWindow?, destroy: Bool = true) {
    guard let window else { return }
    if let parent = window.sheetParent {
      parent.endSheet(window)
    }
    window.orderOut(nil)
    if destroy {
      window.contentViewController = nil
    }
    model?.updateMainWindowInteraction()
  }
}

@MainActor
final class QuitSheetController {
  private weak var model: AppModel?
  private let window: NSWindow

  init(model: AppModel) {
    self.model = model
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 458, height: 188),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Quit Cuelixa"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.isMovable = false
    window.contentViewController = NSHostingController(
      rootView: QuitSheet().environmentObject(model))
  }

  func show() {
    guard let parent = model?.resolveMainWindow() else {
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      return
    }
    parent.makeKeyAndOrderFront(nil)
    if window.sheetParent == nil {
      parent.beginSheet(window)
    } else {
      window.makeKey()
    }
    model?.updateMainWindowInteraction()
    NSApp.activate()
  }

  func hide() {
    if let parent = window.sheetParent {
      parent.endSheet(window)
    }
    window.orderOut(nil)
    model?.updateMainWindowInteraction()
  }

  func focus() {
    if window.sheetParent == nil {
      show()
    } else {
      window.makeKey()
    }
  }
}
