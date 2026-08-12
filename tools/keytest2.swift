import Cocoa
setbuf(stdout, nil)
let src = CGEventSource(stateID: .hidSystemState)
print("firing Ctrl+Right (switch space) in 2s...")
Thread.sleep(forTimeInterval: 2.0)
let d = CGEvent(keyboardEventSource: src, virtualKey: 0x7C, keyDown: true)
let u = CGEvent(keyboardEventSource: src, virtualKey: 0x7C, keyDown: false)
d?.flags = .maskControl
u?.flags = .maskControl
d?.post(tap: .cghidEventTap)
u?.post(tap: .cghidEventTap)
print("fired")
