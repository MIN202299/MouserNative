import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case buttons
    case pointerScroll
    case battery
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .buttons: String(localized: "Buttons")
        case .pointerScroll: String(localized: "Pointer & Scroll")
        case .battery: String(localized: "Battery")
        case .general: String(localized: "General")
        }
    }

    var systemImage: String {
        switch self {
        case .buttons: "computermouse"
        case .pointerScroll: "scroll"
        case .battery: "battery.100"
        case .general: "gearshape"
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

private enum AppVersion {
    static let displayString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return AppVersionFormatter.sidebarText(version: version)
    }()
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
                    Label(tab.title, systemImage: tab.systemImage)
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

            Text(AppVersion.displayString)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fontDesign(.monospaced)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyleSoftIfAvailable()
        .navigationTitle(String(localized: "Mouser Settings"))
    }
}

private struct DeviceHeaderView: View {
    let connected: Bool
    let name: String
    let inputMonitoringGranted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image("MouseAnywhere3S")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 36)
                .opacity(connected ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 1) {
                Text(connected ? name : String(localized: "No mouse connected"))
                    .font(.headline)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(inputMonitoringGranted ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 4)
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
            case .battery: BatteryPane()
            case .general: GeneralPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
