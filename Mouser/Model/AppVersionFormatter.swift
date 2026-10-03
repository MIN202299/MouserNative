enum AppVersionFormatter {
    static func sidebarText(version: String) -> String {
        "v\(version)"
    }

    static func aboutText(version: String) -> String {
        "Version \(version)"
    }
}
