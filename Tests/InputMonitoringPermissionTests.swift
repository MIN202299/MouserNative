import IOKit.hid

@main
struct InputMonitoringPermissionTests {
    static func main() {
        var access = kIOHIDAccessTypeDenied
        let permission = InputMonitoringPermission(
            checkAccess: { access },
            requestAccess: {
                access = kIOHIDAccessTypeGranted
                return true
            }
        )

        precondition(permission.status == .denied, "Denied HID access must be visible to the app")
        precondition(permission.request(), "The system HID access request result must be returned")
        precondition(permission.status == .granted, "Permission status must refresh after access is granted")

        let unknown = InputMonitoringPermission(
            checkAccess: { kIOHIDAccessTypeUnknown },
            requestAccess: { false }
        )
        precondition(unknown.status == .unknown, "An undecided TCC state must not be reported as denied")

        print("Input monitoring permission tests passed")
    }
}
