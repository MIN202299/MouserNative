import Cocoa
setbuf(stdout, nil)
print("volume up in 1s...")
Thread.sleep(forTimeInterval: 1.0)

func mediaEvent(_ key: Int32, down: Bool) -> CGEvent? {
    let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
    let ev = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
    )
    return ev?.cgEvent
}

if let d = mediaEvent(0, down: true) { d.post(tap: .cghidEventTap) }
if let u = mediaEvent(0, down: false) { u.post(tap: .cghidEventTap) }
print("volume up fired")
