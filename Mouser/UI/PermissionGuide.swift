import AppKit
import SwiftUI

/// The macOS privacy permissions Mouser asks for.
enum PrivacyPermission: String, CaseIterable, Identifiable {
    case accessibility
    case inputMonitoring

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .inputMonitoring: String(localized: "Input Monitoring")
        }
    }

    var detail: String {
        switch self {
        case .accessibility:
            String(localized: "Lets Mouser perform remapped actions like shortcuts and clicks.")
        case .inputMonitoring:
            String(localized: "Lets Mouser talk to your Logitech mouse over Bluetooth.")
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard.badge.eye"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }
}

extension PermissionManager {
    func isGranted(_ permission: PrivacyPermission) -> Bool {
        switch permission {
        case .accessibility: accessibilityGranted
        case .inputMonitoring: inputMonitoringGranted
        }
    }
}

/// Opens the matching System Settings pane and floats a small panel next to it
/// from which the user can drag Mouser.app straight into the permission list.
@MainActor
final class PermissionGuideController {
    static let shared = PermissionGuideController()

    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private var model = PermissionGuideModel()
    private var lastSettingsFrame: CGRect?

    private static let panelHeight: CGFloat = 92
    private static let fallbackWidth: CGFloat = 560
    private static let settingsBundleID = "com.apple.systempreferences"

    private init() {}

    private var isPreview = false

    /// `preview` shows the panel even when the permission is already granted
    /// (used by the `-previewPermissionGuide` launch argument).
    func show(_ permission: PrivacyPermission, preview: Bool = false) {
        let permissions = PermissionManager.shared
        permissions.refresh()
        guard preview || !permissions.isGranted(permission) else { return }
        isPreview = preview

        if let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        }

        model.permission = permission
        model.granted = false
        lastSettingsFrame = nil

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, animated: false)
        panel.orderFrontRegardless()
        startTracking()
    }

    func close() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.fallbackWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: PermissionGuideView(model: model) { [weak self] in
            self?.close()
        })
        hosting.frame = NSRect(x: 0, y: 0, width: Self.fallbackWidth, height: Self.panelHeight)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let panel, let permission = model.permission else { return }
        let permissions = PermissionManager.shared
        permissions.refresh()

        if !isPreview, permissions.isGranted(permission), !model.granted {
            withAnimation(.spring(duration: 0.35)) { model.granted = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self, self.model.granted else { return }
                self.close()
            }
            return
        }

        let settingsRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.settingsBundleID).isEmpty
        if !settingsRunning, !model.granted {
            close()
            return
        }
        position(panel, animated: true)
    }

    /// Docks the panel directly under the System Settings window at the same
    /// width; if there is no room below, it sits inside the window's bottom edge.
    private func position(_ panel: NSPanel, animated: Bool) {
        let settingsFrame = Self.systemSettingsWindowFrame()
        if let settingsFrame, settingsFrame == lastSettingsFrame, panel.isVisible { return }
        lastSettingsFrame = settingsFrame

        let height = Self.panelHeight
        let frame: NSRect
        if let settingsFrame {
            let screen = NSScreen.screens.first { $0.frame.intersects(settingsFrame) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? settingsFrame
            var y = settingsFrame.minY - height - 8
            if y < visible.minY + 4 {
                y = settingsFrame.minY + 12
            }
            frame = NSRect(x: settingsFrame.minX, y: y, width: settingsFrame.width, height: height)
        } else {
            let visible = NSScreen.main?.visibleFrame ?? .zero
            let width = Self.fallbackWidth
            frame = NSRect(x: visible.midX - width / 2, y: visible.minY + 40, width: width, height: height)
        }
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }

    /// Frame of the frontmost System Settings window in Cocoa (bottom-left) coordinates.
    /// Window bounds and owner PID are readable without Screen Recording permission.
    private static func systemSettingsWindowFrame() -> CGRect? {
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID)
                .map(\.processIdentifier)
        )
        guard !pids.isEmpty,
              let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 300, bounds.height > 200
            else { continue }

            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return CGRect(
                x: bounds.minX,
                y: primaryHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
        }
        return nil
    }
}

@MainActor
@Observable
final class PermissionGuideModel {
    var permission: PrivacyPermission?
    var granted = false
}

private struct PermissionGuideView: View {
    let model: PermissionGuideModel
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            DraggableAppIcon()

            VStack(alignment: .leading, spacing: 4) {
                if model.granted {
                    Label(String(localized: "Permission granted"), systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else {
                    Text(String(localized: "Can't find \(appName)?"))
                        .font(.headline)
                    Text(instructionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if hovering && !model.granted {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .help(String(localized: "Close"))
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: model.granted)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Mouser"
    }

    private var instructionText: String {
        let name = model.permission?.title ?? ""
        return String(localized: "Drag the icon into the “\(name)” list, then turn on the switch.")
    }
}

/// The app icon users drag into System Settings. Drawing is SwiftUI; the drag
/// itself is an AppKit dragging session carrying Mouser.app's file URL.
private struct DraggableAppIcon: View {
    @State private var hovering = false

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 52, height: 52)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.04))
            }
            .scaleEffect(hovering ? 1.05 : 1)
            .overlay { AppDragSourceView() }
            .onHover { hovering = $0 }
            .animation(.spring(duration: 0.25), value: hovering)
            .help(String(localized: "Drag me"))
    }
}

private struct AppDragSourceView: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragSourceNSView { AppDragSourceNSView() }
    func updateNSView(_ nsView: AppDragSourceNSView, context: Context) {}
}

final class AppDragSourceNSView: NSView, NSDraggingSource {
    private var mouseDownEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        mouseDownEvent = nil

        let url = Bundle.main.bundleURL as NSURL
        let item = NSDraggingItem(pasteboardWriter: url)
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let iconSize = NSSize(width: 48, height: 48)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: point.x - iconSize.width / 2, y: point.y - iconSize.height / 2,
                   width: iconSize.width, height: iconSize.height),
            contents: icon
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}
