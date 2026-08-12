import AppKit
import CoreGraphics
import Foundation

/// Marker on synthesized events so the interceptor ignores our own output.
enum EventMarker {
    static let injected: Int64 = 0x4D4F5554 // "MOUT"

    static func isInjected(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == injected
    }

    static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: injected)
    }
}

/// Executes mapped actions by synthesizing HID-level events.
@MainActor
final class ActionPerformer {
    static let shared = ActionPerformer()

    private init() {}

    func perform(_ action: MouseAction) {
        switch action {
        case .missionControl: SystemActions.missionControl(); return
        case .appExpose: SystemActions.appExpose(); return
        case .launchpad: SystemActions.launchpad(); return
        case .spotlight: SystemActions.spotlight(); return
        case .spaceLeft: SystemActions.switchSpace(left: true); return
        case .spaceRight: SystemActions.switchSpace(left: false); return
        case .screenshot: SystemActions.screenshot(); return
        default: break
        }

        if let combo = action.keyCombo {
            postKeyCombo(flags: combo.flags, key: combo.key)
        } else if let mediaKey = action.mediaKey {
            postMediaKey(mediaKey)
        } else if let button = action.mouseClick {
            postMouseClick(button: button)
        }
    }

    private func postKeyCombo(flags: CGEventFlags, key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        EventMarker.tag(down)
        EventMarker.tag(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postMediaKey(_ nxKey: Int32) {
        func makeEvent(down: Bool) -> CGEvent? {
            let data1 = Int((nxKey << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            return event?.cgEvent
        }
        if let down = makeEvent(down: true) {
            EventMarker.tag(down)
            down.post(tap: .cghidEventTap)
        }
        if let up = makeEvent(down: false) {
            EventMarker.tag(up)
            up.post(tap: .cghidEventTap)
        }
    }

    private func postMouseClick(button: Int) {
        let position = CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)

        func post(type: CGEventType, cgButton: CGMouseButton) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: position, mouseButton: cgButton) else { return }
            EventMarker.tag(event)
            event.post(tap: .cghidEventTap)
        }

        switch button {
        case 0:
            post(type: .leftMouseDown, cgButton: .left)
            post(type: .leftMouseUp, cgButton: .left)
        case 1:
            post(type: .rightMouseDown, cgButton: .right)
            post(type: .rightMouseUp, cgButton: .right)
        default:
            guard let cgButton = CGMouseButton(rawValue: UInt32(button)) else { return }
            post(type: .otherMouseDown, cgButton: cgButton)
            post(type: .otherMouseUp, cgButton: cgButton)
        }
    }
}
