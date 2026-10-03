import IOKit.hid

enum InputMonitoringPermissionStatus: Equatable {
    case granted
    case denied
    case unknown
}

/// Small testable boundary around macOS Input Monitoring (ListenEvent) TCC APIs.
struct InputMonitoringPermission {
    private let checkAccess: () -> IOHIDAccessType
    private let requestAccess: () -> Bool

    init(
        checkAccess: @escaping () -> IOHIDAccessType = {
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        },
        requestAccess: @escaping () -> Bool = {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    ) {
        self.checkAccess = checkAccess
        self.requestAccess = requestAccess
    }

    var status: InputMonitoringPermissionStatus {
        switch checkAccess() {
        case kIOHIDAccessTypeGranted:
            .granted
        case kIOHIDAccessTypeDenied:
            .denied
        default:
            .unknown
        }
    }

    @discardableResult
    func request() -> Bool {
        requestAccess()
    }
}
