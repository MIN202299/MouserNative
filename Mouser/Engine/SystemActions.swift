import AppKit

// SkyLight/CoreDock private APIs (same symbols the Python Mouser uses).
// Plain synthesized keystrokes posted to the HID tap are ignored by WindowServer's
// symbolic-hotkey handler — these call the window server / Dock directly instead.
@_silgen_name("CGSGetSymbolicHotKeyValue") private func CGSGetSymbolicHotKeyValue(_ hotkey: UInt32, _ keyEquivalent: UnsafeMutablePointer<UInt16>?, _ virtualKey: UnsafeMutablePointer<UInt16>?, _ modifiers: UnsafeMutablePointer<UInt32>?) -> Int32
@_silgen_name("CGSIsSymbolicHotKeyEnabled") private func CGSIsSymbolicHotKeyEnabled(_ hotkey: UInt32) -> Bool
@_silgen_name("CGSSetSymbolicHotKeyEnabled") private func CGSSetSymbolicHotKeyEnabled(_ hotkey: UInt32, _ enabled: Bool) -> Int32
@_silgen_name("CoreDockSendNotification") private func CoreDockSendNotification(_ notification: CFString, _ unknown: Int32) -> Int32

/// System-level actions that cannot be performed by posting keyboard shortcuts.
@MainActor
enum SystemActions {
    static func missionControl() {
        openApp(at: "/System/Applications/Mission Control.app")
    }

    static func launchpad() {
        if FileManager.default.fileExists(atPath: "/System/Applications/Launchpad.app") {
            openApp(at: "/System/Applications/Launchpad.app")
        } else {
            openApp(at: "/System/Applications/Apps.app") // macOS 26 replaced Launchpad
        }
    }

    static func spotlight() {
        openApp(at: "/System/Library/CoreServices/Spotlight.app")
    }

    static func screenshot() {
        openApp(at: "/System/Library/CoreServices/screencaptureui.app")
    }

    private static func openApp(at path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                Notifier.shared.notifyFailure(String(localized: "Could not open the system component."))
            }
        }
    }

    // MARK: - Space switching via symbolic hotkeys

    /// Hotkey IDs 79/81 are "Move left/right a space". The configured binding is
    /// read live, so user-remapped shortcuts are respected. The event must be
    /// posted to the session event tap — the HID tap is ignored by the
    /// symbolic-hotkey handler.
    static func switchSpace(left: Bool) {
        let hotkey: UInt32 = left ? 79 : 81
        var keyEquivalent: UInt16 = 0
        var virtualKey: UInt16 = 0
        var modifiers: UInt32 = 0
        guard CGSGetSymbolicHotKeyValue(hotkey, &keyEquivalent, &virtualKey, &modifiers) == 0 else { return }

        let wasEnabled = CGSIsSymbolicHotKeyEnabled(hotkey)
        if !wasEnabled { _ = CGSSetSymbolicHotKeyEnabled(hotkey, true) }
        defer { if !wasEnabled { _ = CGSSetSymbolicHotKeyEnabled(hotkey, false) } }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(virtualKey), keyDown: false) else { return }
        down.flags = CGEventFlags(rawValue: UInt64(modifiers))
        up.flags = CGEventFlags(rawValue: UInt64(modifiers))
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        // Let WindowServer act before the hotkey is re-disabled.
        usleep(50_000)
    }

    // MARK: - App Exposé via Dock notification

    static func appExpose() {
        if CoreDockSendNotification("com.apple.expose.front.awake" as CFString, 0) != 0 {
            Notifier.shared.notifyFailure(String(localized: "App Exposé is unavailable right now."))
        }
    }
}
