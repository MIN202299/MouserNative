import Cocoa
setbuf(stdout, nil)
let which = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "f3"
print("firing \(which) in 2s...")
Thread.sleep(forTimeInterval: 2.0)

switch which {
case "f3":
    // Plain F3 key press (Apple keyboards map F3 to Mission Control by default).
    let src = CGEventSource(stateID: .hidSystemState)
    let d = CGEvent(keyboardEventSource: src, virtualKey: 0x63, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: 0x63, keyDown: false)
    d?.post(tap: .cghidEventTap)
    u?.post(tap: .cghidEventTap)
    print("f3 fired")
case "mc":
    // Launch Mission Control.app directly.
    let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, err in
        print("open MC: \(err?.localizedDescription ?? "ok")")
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(3))
default:
    print("unknown")
}
