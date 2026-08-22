// SPDX-License-Identifier: Apache-2.0
import AppKit

final class CuelixaSeekSlider: NSSlider {
  var onBegin: ((Double) -> Void)?
  var onChange: ((Double) -> Void)?
  var onEnd: ((Double) -> Void)?
  fileprivate(set) var dragging = false
  private var scrollAccumulator: Double = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    target = self
    action = #selector(valueChanged(_:))
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    target = self
    action = #selector(valueChanged(_:))
  }

  @objc private func valueChanged(_ sender: NSSlider) {
    if dragging {
      onChange?(doubleValue)
    } else {
      onBegin?(doubleValue)
      onChange?(doubleValue)
      onEnd?(doubleValue)
    }
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    dragging = true
    onBegin?(doubleValue)
    super.mouseDown(with: event)
    dragging = false
    onEnd?(doubleValue)
  }

  override func scrollWheel(with event: NSEvent) {
    let raw =
      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
      ? event.scrollingDeltaX : event.scrollingDeltaY
    guard raw != 0 else {
      super.scrollWheel(with: event)
      return
    }
    if event.hasPreciseScrollingDeltas {
      scrollAccumulator += raw / 8
    } else {
      scrollAccumulator += raw > 0 ? 1 : -1
    }
    let wholeSteps = Int(scrollAccumulator.rounded(.towardZero))
    guard wholeSteps != 0 else { return }
    scrollAccumulator -= Double(wholeSteps)
    let adjusted = max(minValue, min(maxValue, doubleValue + Double(wholeSteps)))
    onBegin?(doubleValue)
    doubleValue = adjusted
    onChange?(adjusted)
    onEnd?(adjusted)
  }
}
