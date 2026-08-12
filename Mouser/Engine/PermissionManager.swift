import AppKit
import ApplicationServices
import Foundation

/// Tracks macOS Accessibility permission and fires when granted.
@MainActor
@Observable
final class PermissionManager {
    static let shared = PermissionManager()

    private(set) var accessibilityGranted = false
    var onAccessibilityGranted: (() -> Void)?
    private var pollTimer: Timer?

    private init() {}

    func start() {
        refresh()
        guard !accessibilityGranted else { return }
        prompt()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
            if trusted {
                pollTimer?.invalidate()
                pollTimer = nil
                onAccessibilityGranted?()
            }
        }
    }

    func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
