import Cocoa

// Space switching via SkyLight private API (same mechanism as yabai).
@_silgen_name("SLSMainConnectionID") func SLSMainConnectionID() -> Int32
@_silgen_name("SLSCopyManagedDisplaySpaces") func SLSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray
@_silgen_name("SLSManagedDisplaySetCurrentSpace") func SLSManagedDisplaySetCurrentSpace(_ cid: Int32, _ displayUUID: CFString, _ spaceID: UInt64)

setbuf(stdout, nil)
let direction = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "left"

let cid = SLSMainConnectionID()
let displays = SLSCopyManagedDisplaySpaces(cid) as! [[String: Any]]
print("displays: \(displays.count)")

for display in displays {
    guard let id = display["Display Identifier"] as? String else { continue }
    print("display \(id)")
    let spaces = display["Spaces"] as! [[String: Any]]
    let current = (display["Current Space"] as! [String: Any])["id64"] as! UInt64
    print("current space: \(current), user spaces: \(spaces.count)")

    // Only user desktops (type 0); skip fullscreen-app spaces.
    let userSpaces = spaces.filter { ($0["type"] as? Int) == 0 }
    guard let index = userSpaces.firstIndex(where: { ($0["id64"] as? UInt64) == current }) else {
        print("current space not a user space (fullscreen?) — wrapping to nearest")
        continue
    }
    let targetIndex = direction == "left" ? max(0, index - 1) : min(userSpaces.count - 1, index + 1)
    if targetIndex == index { print("already at \(direction == "left" ? "leftmost" : "rightmost")"); exit(0) }
    let target = userSpaces[targetIndex]["id64"] as! UInt64
    print("switching to space \(target)")
    SLSManagedDisplaySetCurrentSpace(cid, id as CFString, target)
    print("switched")
    exit(0)
}
print("main display not found in SLS list")
