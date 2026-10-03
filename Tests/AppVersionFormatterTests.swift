@main
struct AppVersionFormatterTests {
    static func main() {
        precondition(
            AppVersionFormatter.sidebarText(version: "1.0.2") == "v1.0.2",
            "The sidebar must show only the incrementing marketing version"
        )
        precondition(
            AppVersionFormatter.aboutText(version: "1.0.2") == "Version 1.0.2",
            "The About pane must not expose the internal build number"
        )

        print("App version formatter tests passed")
    }
}
