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

    private static let panelSize = CGSize(width: 380, height: 168)
    private static let settingsBundleID = "com.apple.systempreferences"

    private init() {}

    func show(_ permission: PrivacyPermission) {
        let permissions = PermissionManager.shared
        permissions.refresh()
        guard !permissions.isGranted(permission) else { return }

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
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
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

        if permissions.isGranted(permission), !model.granted {
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

    /// Places the panel just below the System Settings window (centered on it),
    /// falling back to overlapping its bottom edge or the screen's bottom center.
    private func position(_ panel: NSPanel, animated: Bool) {
        let size = Self.panelSize
        let settingsFrame = Self.systemSettingsWindowFrame()
        if let settingsFrame, settingsFrame == lastSettingsFrame, panel.isVisible { return }
        lastSettingsFrame = settingsFrame

        var origin: CGPoint
        if let settingsFrame {
            let screen = NSScreen.screens.first { $0.frame.intersects(settingsFrame) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? settingsFrame
            origin = CGPoint(x: settingsFrame.midX - size.width / 2, y: settingsFrame.minY - size.height - 10)
            if origin.y < visible.minY + 8 {
                origin.y = settingsFrame.minY + 16
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        } else {
            let visible = NSScreen.main?.visibleFrame ?? .zero
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 40)
        }

        let frame = NSRect(origin: origin, size: size)
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
    @State private var nudge = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .help(String(localized: "Close"))
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.granted {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: model.granted)
                Text(String(localized: "Permission granted"))
                    .font(.headline)
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tint)
                        .offset(y: nudge ? -3 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Drag Mouser into the list above"))
                            .font(.headline)
                        Text(instructionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, 20)

                DraggableAppTile()
                    .frame(height: 64)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    nudge = true
                }
            }
        }
    }

    private var instructionText: String {
        let name = model.permission?.title ?? ""
        return String(localized: "Drop it into “\(name)”, then turn on the switch next to Mouser.")
    }
}

/// The app tile users drag into System Settings. Drawing is SwiftUI; the drag
/// itself is an AppKit dragging session carrying Mouser.app's file URL.
private struct DraggableAppTile: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.body.weight(.semibold))
                Text(String(localized: "Drag me"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "hand.draw")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(hovering ? 0.8 : 0.45),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        }
        .overlay { AppDragSourceView() }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Mouser"
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
