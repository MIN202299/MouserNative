import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case buttons
    case pointerScroll
    case smoothScroll
    case battery
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .buttons: String(localized: "Buttons")
        case .pointerScroll: String(localized: "Pointer & Scroll")
        case .smoothScroll: String(localized: "Smooth Scrolling")
        case .battery: String(localized: "Battery")
        case .general: String(localized: "General")
        }
    }

    /// Sidebar icon, drawn in the same thin rounded line style as the menu
    /// bar icon: the Buttons tab reuses the menu bar mouse (Basil), the rest
    /// are Solar "linear" icons (480 Design, CC BY 4.0) via Iconify.
    var icon: Image {
        switch self {
        case .buttons: Image("MenuBarIcon")
        case .pointerScroll: Image("SidebarPointer")
        case .smoothScroll: Image("SidebarScroll")
        case .battery: Image("SidebarBattery")
        case .general: Image("SidebarGeneral")
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    var selectedTab: SettingsTab? = .buttons

    private init() {}
}

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared
    @State private var navigationHistory: [SettingsTab] = [.buttons]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    private var activeTab: SettingsTab {
        navigation.selectedTab ?? .buttons
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebarView(selectedTab: $navigation.selectedTab)
                .frame(width: 200)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(tab: activeTab)
        }
        .navigationTitle(String(localized: "Mouser Settings"))
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

                Button { goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
            }
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            recordNavigation()
        }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation, let tab = navigation.selectedTab else { return }
        if navigationHistory.last == tab { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(tab)
        historyIndex = navigationHistory.count - 1
    }
}

private struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab?
    @State private var deviceState = DeviceState.shared
    @State private var permissions = PermissionManager.shared

    var body: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach(SettingsTab.allCases) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        SidebarIcon(image: tab.icon)
                    }
                    .foregroundStyle(.primary)
                        .tag(tab)
                }
            } header: {
                DeviceHeaderView(
                    connected: deviceState.connected,
                    name: deviceState.deviceName,
                    inputMonitoringGranted: permissions.inputMonitoringGranted
                )
            }

        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyleSoftIfAvailable()
        .navigationTitle(String(localized: "Mouser Settings"))
    }
}

/// Draws every sidebar icon in the same fixed box with the same rendering.
private struct SidebarIcon: View {
    let image: Image

    var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 18, height: 18)
    }
}

private struct DeviceHeaderView: View {
    let connected: Bool
    let name: String
    let inputMonitoringGranted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image("MouseAnywhere3SThumb")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 40)
                .opacity(connected ? 1 : 0.35)
                .saturation(connected ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(connected ? name : String(localized: "No mouse connected"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .padding(.bottom, 8)
        .textCase(nil)
    }

    private var statusColor: Color {
        if connected { return .green }
        return inputMonitoringGranted ? .orange : .red
    }

    private var statusText: String {
        if connected {
            return String(localized: "Connected")
        }
        if !inputMonitoringGranted {
            return String(localized: "Input Monitoring permission required")
        }
        return String(localized: "Waiting for device…")
    }
}

private struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .buttons: ButtonsPane()
            case .pointerScroll: PointerScrollPane()
            case .smoothScroll: SmoothScrollPane()
            case .battery: BatteryPane()
            case .general: GeneralPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .top, spacing: 0) {
            PermissionBanner()
        }
    }
}

/// Shown above every pane while a required permission is missing.
private struct PermissionBanner: View {
    @State private var permissions = PermissionManager.shared

    private var missing: [PrivacyPermission] {
        PrivacyPermission.allCases.filter { !permissions.isGranted($0) }
    }

    var body: some View {
        if let first = missing.first {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Mouser needs your permission"))
                        .font(.subheadline.weight(.semibold))
                    Text(missing.map(\.title).formatted(.list(type: .and)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Allow…")) {
                    PermissionGuideController.shared.show(first)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
