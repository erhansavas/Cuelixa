// SPDX-License-Identifier: Apache-2.0
import Carbon.HIToolbox
import Foundation
import OSLog

/// Registers the finite Cuelixa shortcut set with Carbon's hot-key API. This is
/// intentionally narrower than global NSEvent surveillance and therefore does
/// not require broad Accessibility/Input Monitoring capture.
@MainActor
final class HotKeyManager {
  static let shared = HotKeyManager()
  private let logger = Logger(subsystem: "io.github.erhansavas.Cuelixa", category: "HotKeys")

  weak var model: AppModel?
  private var refs: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  private let signature: OSType = 0x4355_454C  // CUEL

  func install(model: AppModel) {
    self.model = model
    guard handler == nil, refs.isEmpty else { return }

    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let ptr = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return noErr }
        var hid = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hid)
        if status == noErr {
          let owner = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
          let hotKeyID = hid.id
          Task { @MainActor in owner.fire(hotKeyID) }
        }
        return noErr
      }, 1, &type, ptr, &handler)

    guard handlerStatus == noErr, handler != nil else {
      handler = nil
      logger.error("Global hot-key event handler registration failed: \(handlerStatus)")
      return
    }

    let mods = UInt32(controlKey | optionKey)
    register(1, key: UInt32(kVK_ANSI_S), mods: mods)
    register(2, key: UInt32(kVK_ANSI_P), mods: mods)
    register(3, key: UInt32(kVK_ANSI_J), mods: mods)
    register(4, key: UInt32(kVK_ANSI_L), mods: mods)
    register(6, key: UInt32(kVK_ANSI_U), mods: mods)
    register(7, key: UInt32(kVK_ANSI_O), mods: mods)
    register(8, key: UInt32(kVK_ANSI_Q), mods: mods)
  }

  func uninstall() {
    for ref in refs {
      let status = UnregisterEventHotKey(ref)
      if status != noErr {
        logger.error("Global hot-key unregistration failed: \(status)")
      }
    }
    refs.removeAll(keepingCapacity: false)
    if let handler {
      let status = RemoveEventHandler(handler)
      if status != noErr {
        logger.error("Global hot-key handler removal failed: \(status)")
      }
      self.handler = nil
    }
    model = nil
  }

  private func register(_ id: UInt32, key: UInt32, mods: UInt32) {
    var ref: EventHotKeyRef?
    let hid = EventHotKeyID(signature: signature, id: id)
    let status = RegisterEventHotKey(key, mods, hid, GetApplicationEventTarget(), 0, &ref)
    if status == noErr, let ref {
      refs.append(ref)
    } else {
      logger.error("Global hot-key \(id) registration failed: \(status)")
    }
  }

  private func fire(_ id: UInt32) {
    guard let m = model else { return }
    switch id {
    case 1: m.showLibraryWindow()
    case 2: m.player.togglePlayPause()
    case 3: m.player.seekRelative(-10)
    case 4: m.player.seekRelative(10)
    case 6: m.player.seekRelative(-30)
    case 7: m.player.seekRelative(30)
    case 8: m.stopPlayback(showLibrary: true)
    default: break
    }
  }
}
