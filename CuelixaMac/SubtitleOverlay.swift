// SPDX-License-Identifier: Apache-2.0
import AppKit

/// Floating, nonactivating playback surface that preserves Cuelixa's original
/// subtitle-study contract: the library is a management window; active playback
/// lives in a lightweight movable overlay whose chrome disappears when idle.
///
/// This controller owns UI only. AVPlayer, subtitle timing, persistence, remote
/// commands and cancellation remain owned by PlaybackController/AppModel.
@MainActor
final class SubtitleOverlayController: NSObject {
  struct Presentation {
    let subtitle: String
    let position: Double
    let duration: Double
    let playing: Bool
  }

  private final class TrackingView: NSView {
    var onActivity: (() -> Void)?
    var onLeave: (() -> Void)?
    var onRightClick: (() -> Void)?
    private var tracking: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard window != nil, tracking == nil else { return }
      let area = NSTrackingArea(
        rect: .zero,
        options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
        owner: self,
        userInfo: nil
      )
      addTrackingArea(area)
      tracking = area
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil, let tracking {
        removeTrackingArea(tracking)
        self.tracking = nil
      }
      super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) { onActivity?() }
    override func mouseMoved(with event: NSEvent) { onActivity?() }
    override func mouseExited(with event: NSEvent) { onLeave?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
  }

  private let panel: NSPanel
  private let root = TrackingView(frame: .zero)
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let controlsEffect = NSGlassEffectView(frame: .zero)
  private let currentTime = NSTextField(labelWithString: "00:00")
  private let remainingTime = NSTextField(labelWithString: "−00:00")
  private let slider = CuelixaSeekSlider(frame: .zero)
  private let playPauseButton: NSButton
  private var hideTimer: Timer?
  private var controlsVisible = true
  private var positionedOnce = false
  private var latestPresentation: Presentation?

  private let onPlayPause: () -> Void
  private let onBack10: () -> Void
  private let onForward10: () -> Void
  private let onBeginScrub: (Double) -> Void
  private let onLiveScrub: (Double) -> Void
  private let onEndScrub: (Double) -> Void
  private let onStop: () -> Void

  init(
    onPlayPause: @escaping () -> Void,
    onBack10: @escaping () -> Void,
    onForward10: @escaping () -> Void,
    onBeginScrub: @escaping (Double) -> Void,
    onLiveScrub: @escaping (Double) -> Void,
    onEndScrub: @escaping (Double) -> Void,
    onStop: @escaping () -> Void
  ) {
    self.onPlayPause = onPlayPause
    self.onBack10 = onBack10
    self.onForward10 = onForward10
    self.onBeginScrub = onBeginScrub
    self.onLiveScrub = onLiveScrub
    self.onEndScrub = onEndScrub
    self.onStop = onStop

    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 118),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    playPauseButton = NSButton(
      image: NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        ?? NSImage(),
      target: nil,
      action: nil
    )
    super.init()

    configurePanel()
    configureSubtitle()
    configureControls()
    configureInteraction()
  }

  func present(_ presentation: Presentation, screen: NSScreen?) {
    update(presentation)
    if !positionedOnce || !panel.isVisible {
      positionInitial(on: screen ?? NSScreen.main)
      positionedOnce = true
    }
    panel.orderFrontRegardless()
    revealControls()
  }

  func update(_ presentation: Presentation) {
    latestPresentation = presentation
    subtitleLabel.stringValue = presentation.subtitle
    if controlsVisible { applyControlState(presentation) }
  }

  func revealControls() {
    controlsVisible = true
    controlsEffect.isHidden = false
    if let latestPresentation { applyControlState(latestPresentation) }
    scheduleHide()
  }

  func hideControls() {
    guard !slider.dragging else { return }
    hideTimer?.invalidate()
    hideTimer = nil
    controlsVisible = false
    controlsEffect.isHidden = true
  }

  func hide() {
    hideTimer?.invalidate()
    hideTimer = nil
    panel.orderOut(nil)
  }

  func shutdown() {
    hide()
    panel.contentView = nil
  }

  private func applyControlState(_ presentation: Presentation) {
    currentTime.stringValue = clock(presentation.position)
    remainingTime.stringValue = remainingClock(
      position: presentation.position, duration: presentation.duration)
    slider.maxValue = max(1, presentation.duration)
    if !slider.dragging {
      slider.doubleValue = max(0, min(slider.maxValue, presentation.position))
    }
    let symbol = presentation.playing ? "pause.fill" : "play.fill"
    let description = presentation.playing ? "Pause" : "Play"
    playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    playPauseButton.setAccessibilityLabel(description)
  }

  private func configurePanel() {
    panel.title = "Cuelixa Player"
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovableByWindowBackground = true
    panel.acceptsMouseMovedEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.contentView = root
    root.wantsLayer = true
  }

  private func configureSubtitle() {
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
    subtitleLabel.textColor = .white
    subtitleLabel.alignment = .center
    subtitleLabel.maximumNumberOfLines = 3
    subtitleLabel.lineBreakMode = .byWordWrapping
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
    shadow.shadowBlurRadius = 4
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    subtitleLabel.shadow = shadow

    root.addSubview(subtitleLabel)
    NSLayoutConstraint.activate([
      subtitleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      subtitleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      subtitleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
      subtitleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
    ])
  }

  private func configureControls() {
    controlsEffect.translatesAutoresizingMaskIntoConstraints = false
    controlsEffect.style = .regular
    controlsEffect.cornerRadius = 16
    controlsEffect.tintColor = CuelixaDesign.identityAccentNS.withAlphaComponent(0.08)
    root.addSubview(controlsEffect)

    currentTime.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    remainingTime.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    currentTime.textColor = .secondaryLabelColor
    remainingTime.textColor = .secondaryLabelColor
    currentTime.alignment = .right
    remainingTime.alignment = .left

    slider.minValue = 0
    slider.maxValue = 1
    slider.controlSize = .small
    slider.sliderType = .linear
    slider.trackFillColor = CuelixaDesign.identityAccentNS
    slider.tintProminence = .primary
    slider.setAccessibilityLabel("Playback position")
    slider.onBegin = { [weak self] value in
      self?.revealControls()
      self?.onBeginScrub(value)
    }
    slider.onChange = { [weak self] value in
      self?.onLiveScrub(value)
      self?.currentTime.stringValue = self?.clock(value) ?? "00:00"
    }
    slider.onEnd = { [weak self] value in
      self?.onEndScrub(value)
      self?.revealControls()
    }

    let back = symbolButton("gobackward.10", label: "Back 10 seconds", action: #selector(back10))
    playPauseButton.target = self
    playPauseButton.action = #selector(playPause)
    configureSymbolButton(playPauseButton, label: "Pause")
    playPauseButton.contentTintColor = CuelixaDesign.identityAccentNS
    let forward = symbolButton(
      "goforward.10", label: "Forward 10 seconds", action: #selector(forward10))
    let close = symbolButton("xmark", label: "Stop playback", action: #selector(stop))

    let timeline = NSStackView(views: [currentTime, slider, remainingTime])
    timeline.orientation = .horizontal
    timeline.alignment = .centerY
    timeline.spacing = 8
    slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
    slider.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
    currentTime.widthAnchor.constraint(equalToConstant: 42).isActive = true
    remainingTime.widthAnchor.constraint(equalToConstant: 48).isActive = true

    let transport = NSStackView(views: [back, playPauseButton, forward, close])
    transport.orientation = .horizontal
    transport.alignment = .centerY
    transport.spacing = 2

    let separator = NSBox(frame: .zero)
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.heightAnchor.constraint(equalToConstant: 18).isActive = true

    let content = NSStackView(views: [timeline, separator, transport])
    content.orientation = .horizontal
    content.alignment = .centerY
    content.spacing = 8
    content.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 10)
    controlsEffect.contentView = content

    NSLayoutConstraint.activate([
      controlsEffect.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      controlsEffect.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
      controlsEffect.leadingAnchor.constraint(
        greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
      controlsEffect.trailingAnchor.constraint(
        lessThanOrEqualTo: root.trailingAnchor, constant: -16),
      controlsEffect.topAnchor.constraint(
        greaterThanOrEqualTo: subtitleLabel.bottomAnchor, constant: 4),
    ])
  }

  private func configureInteraction() {
    root.onActivity = { [weak self] in self?.revealControls() }
    root.onLeave = { [weak self] in self?.hideControls() }
    root.onRightClick = { [weak self] in
      guard let self else { return }
      self.controlsVisible ? self.hideControls() : self.revealControls()
    }
  }

  private func symbolButton(_ symbol: String, label: String, action: Selector) -> NSButton {
    let button = NSButton(
      image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
      target: self,
      action: action
    )
    configureSymbolButton(button, label: label)
    return button
  }

  private func configureSymbolButton(_ button: NSButton, label: String) {
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.controlSize = .small
    button.contentTintColor = .labelColor
    button.setAccessibilityLabel(label)
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
  }

  private func scheduleHide() {
    hideTimer?.invalidate()
    let timer = Timer(
      timeInterval: 3.6,
      target: self,
      selector: #selector(autoHideTimerFired(_:)),
      userInfo: nil,
      repeats: false
    )
    timer.tolerance = 0.35
    hideTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  @objc private func autoHideTimerFired(_ timer: Timer) {
    guard timer === hideTimer else { return }
    hideTimer = nil
    hideControls()
  }

  private func positionInitial(on screen: NSScreen?) {
    guard let frame = screen?.visibleFrame else { return }
    let width = min(760, max(540, frame.width - 180))
    let height: CGFloat = 118
    panel.setContentSize(NSSize(width: width, height: height))
    panel.setFrameOrigin(
      NSPoint(x: frame.midX - width / 2, y: frame.minY + 68)
    )
  }

  private func clock(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "00:00" }
    let seconds = Int(value.rounded(.down))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  private func remainingClock(position: Double, duration: Double) -> String {
    guard position.isFinite, duration.isFinite, duration >= 0 else { return "−00:00" }
    return "−" + clock(max(0, duration - position))
  }

  @objc private func back10() {
    revealControls()
    onBack10()
  }

  @objc private func playPause() {
    revealControls()
    onPlayPause()
  }

  @objc private func forward10() {
    revealControls()
    onForward10()
  }

  @objc private func stop() {
    onStop()
  }
}
