import Cocoa

// Minimal otherMouse event monitor: prints button numbers for 20 seconds.
setbuf(stdout, nil)

guard AXIsProcessTrusted() else {
    print("accessibility NOT granted for this process")
    exit(1)
}

let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
    | (1 << CGEventType.otherMouseUp.rawValue)
    | (1 << CGEventType.leftMouseDown.rawValue)
    | (1 << CGEventType.rightMouseDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, type, event, _ in
        let btn = event.getIntegerValueField(.mouseEventButtonNumber)
        print("event type=\(type.rawValue) button=\(btn)")
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
) else {
    print("tapCreate failed")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("listening for 25s — press mouse buttons now")
DispatchQueue.main.asyncAfter(deadline: .now() + 25) { exit(0) }
RunLoop.main.run()
