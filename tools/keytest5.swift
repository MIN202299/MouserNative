import Cocoa
setbuf(stdout, nil)
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "click"

if mode == "click" {
    // Synthesized left click at a wallpaper point (dismisses Mission Control).
    let point = CGPoint(x: 1050, y: 1000)
    print("click at \(point) in 1s")
    Thread.sleep(forTimeInterval: 1.0)
    let src = CGEventSource(stateID: .hidSystemState)
    let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    d?.post(tap: .cghidEventTap)
    u?.post(tap: .cghidEventTap)
    print("clicked")
} else if mode == "type" {
    // Type "mouser" into whatever has focus.
    let src = CGEventSource(stateID: .hidSystemState)
    print("typing in 1s")
    Thread.sleep(forTimeInterval: 1.0)
    for char: CGKeyCode in [46, 24, 32, 1, 14, 4] { // m o u s e r
        let d = CGEvent(keyboardEventSource: src, virtualKey: char, keyDown: true)
        let u = CGEvent(keyboardEventSource: src, virtualKey: char, keyDown: false)
        d?.post(tap: .cghidEventTap)
        u?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    print("typed")
}
