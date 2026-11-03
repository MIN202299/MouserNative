import AppKit
import SwiftUI

/// First-run window that walks the user through granting Mouser's permissions.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: OnboardingWindowController?

    static func showIfNeeded() {
        let permissions = PermissionManager.shared
        permissions.refresh()
        guard !permissions.accessibilityGranted || !permissions.inputMonitoringGranted else { return }
        show()
    }

    static func show() {
        if shared == nil {
            shared = OnboardingWindowController()
        }
        shared?.showWindow(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 520, height: 470)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = String(localized: "Welcome to Mouser")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: OnboardingView {
            window.close()
        })
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        AppActivationPolicy.enter()
    }

    func windowWillClose(_ notification: Notification) {
        PermissionGuideController.shared.close()
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}

private struct OnboardingView: View {
    let onDone: () -> Void
    @State private var permissions = PermissionManager.shared

    private var allGranted: Bool {
        permissions.accessibilityGranted && permissions.inputMonitoringGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                Text(String(localized: "Welcome to Mouser"))
                    .font(.title.bold())
                Text(String(localized: "Mouser needs two macOS permissions to remap your mouse buttons. Everything stays on this Mac."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(PrivacyPermission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        granted: permissions.isGranted(permission)
                    )
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            HStack {
                if !allGranted {
                    Text(String(localized: "Click Allow, then drag Mouser into the list in System Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(allGranted ? String(localized: "Get Started") : String(localized: "Later")) {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(allGranted ? .accentColor : .gray)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 470)
        .background(.background)
        .animation(.spring(duration: 0.35), value: allGranted)
    }
}

/// Shared permission row used by onboarding and the General pane.
struct PermissionRow: View {
    let permission: PrivacyPermission
    let granted: Bool
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.system(size: compact ? 14 : 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: compact ? 26 : 34, height: compact ? 26 : 34)
                .background(
                    granted ? Color.green.gradient : Color.accentColor.gradient,
                    in: RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(compact ? .body : .headline)
                Text(permission.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if granted {
                Label(String(localized: "Granted"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(String(localized: "Allow…")) {
                    PermissionGuideController.shared.show(permission)
                }
                .controlSize(compact ? .small : .regular)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(compact ? 0 : 14)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .animation(.spring(duration: 0.3), value: granted)
    }
}
