import Cocoa

// Test synthesized Ctrl+Down (App Exposé) with different posting strategies.
// Usage: ./keytest a|b|c   — watches nothing, just fires after a 2s delay.
setbuf(stdout, nil)
let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "a"

let downArrow: CGKeyCode = 0x7D
let ctrlKey: CGKeyCode = 0x3B

func tag(_ e: CGEvent?) -> CGEvent? {
    e?.setIntegerValueField(.eventSourceUserData, value: 0x4D4F5554)
    return e
}

print("firing variant \(variant) in 2s (App Exposé = Ctrl+Down)...")
Thread.sleep(forTimeInterval: 2.0)

let src = CGEventSource(stateID: .hidSystemState)

switch variant {
case "a":
    // Current app approach: flags set on key events only, posted to HID tap.
    let d = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: false)
    d?.flags = .maskControl
    u?.flags = .maskControl
    tag(d)?.post(tap: .cghidEventTap)
    tag(u)?.post(tap: .cghidEventTap)
    print("a fired")

case "b":
    // Explicit modifier down/up (flagsChanged) around the key events.
    let cd = CGEvent(keyboardEventSource: src, virtualKey: ctrlKey, keyDown: true)
    cd?.flags = .maskControl
    tag(cd)?.post(tap: .cghidEventTap)
    usleep(20_000)
    let d = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: true)
    d?.flags = .maskControl
    tag(d)?.post(tap: .cghidEventTap)
    usleep(20_000)
    let u = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: false)
    u?.flags = .maskControl
    tag(u)?.post(tap: .cghidEventTap)
    usleep(20_000)
    let cu = CGEvent(keyboardEventSource: src, virtualKey: ctrlKey, keyDown: false)
    cu?.flags = []
    tag(cu)?.post(tap: .cghidEventTap)
    print("b fired")

case "c":
    // Post to session tap instead of HID tap.
    let d = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: false)
    d?.flags = .maskControl
    u?.flags = .maskControl
    tag(d)?.post(tap: .cgSessionEventTap)
    tag(u)?.post(tap: .cgSessionEventTap)
    print("c fired")

default:
    print("unknown variant")
}
