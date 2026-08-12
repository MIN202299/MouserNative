import Cocoa
setbuf(stdout, nil)
let which = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "esc"
let keyCode: CGKeyCode
let flags: CGEventFlags
switch which {
case "esc": keyCode = 53; flags = []
case "left": keyCode = 0x7B; flags = .maskControl
case "right": keyCode = 0x7C; flags = .maskControl
default: keyCode = 53; flags = []
}
print("firing \(which) in 1s...")
Thread.sleep(forTimeInterval: 1.0)
let src = CGEventSource(stateID: .hidSystemState)
let d = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
let u = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
d?.flags = flags
u?.flags = flags
d?.post(tap: .cghidEventTap)
u?.post(tap: .cghidEventTap)
print("fired \(which)")
