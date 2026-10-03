import AppKit
import ApplicationServices
import Foundation

/// Tracks the two macOS privacy permissions Mouser needs.
@MainActor
@Observable
final class PermissionManager {
    static let shared = PermissionManager()

    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false
    var onAccessibilityGranted: (() -> Void)?
    var onInputMonitoringGranted: (() -> Void)?
    private var pollTimer: Timer?
    private var isSuspended = false
    private let inputMonitoringPermission = InputMonitoringPermission()

    private init() {}

    func start() {
        guard !isSuspended else { return }
        refresh()
        if !accessibilityGranted {
            prompt()
        }
        if !inputMonitoringGranted {
            requestInputMonitoring(openSettingsIfNeeded: false)
        }
        if !accessibilityGranted || !inputMonitoringGranted {
            startPolling()
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func suspendForSleep() {
        guard !isSuspended else { return }
        isSuspended = true
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func resumeAfterWake() {
        guard isSuspended else { return }
        isSuspended = false
        refresh()
        if !accessibilityGranted || !inputMonitoringGranted {
            startPolling()
        }
    }

    func refresh() {
        guard !isSuspended else { return }
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
            if trusted {
                onAccessibilityGranted?()
            }
        }

        let canMonitorInput = inputMonitoringPermission.status == .granted
        if canMonitorInput != inputMonitoringGranted {
            inputMonitoringGranted = canMonitorInput
            if canMonitorInput {
                onInputMonitoringGranted?()
            }
        }

        if accessibilityGranted && inputMonitoringGranted {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoring(openSettingsIfNeeded: Bool = true) {
        _ = inputMonitoringPermission.request()
        refresh()
        if openSettingsIfNeeded && !inputMonitoringGranted {
            openInputMonitoringSettings()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
