import Foundation
import CoreGraphics

/// A remappable mouse button on the MX Anywhere 3S.
enum MouseButton: String, CaseIterable, Identifiable, Codable {
    case middle
    case back = "xbutton1"
    case forward = "xbutton2"
    case modeShift

    var id: String { rawValue }

    /// Quartz "other mouse" button number for standard HID buttons.
    var cgButtonNumber: Int? {
        switch self {
        case .middle: 2
        case .back: 3
        case .forward: 4
        case .modeShift: nil
        }
    }

    /// HID++ control ID (from REPROG_V4 control enumeration on device).
    var controlID: UInt16? {
        switch self {
        case .middle: 0x0052
        case .back: 0x0053
        case .forward: 0x0056
        case .modeShift: HIDPP.CID.modeShift
        }
    }

    /// Position (fraction of image size) in the MX Anywhere 3S diagram.
    var diagramPosition: CGPoint {
        switch self {
        case .middle: CGPoint(x: 0.71, y: 0.16)
        case .back: CGPoint(x: 0.28, y: 0.60)
        case .forward: CGPoint(x: 0.22, y: 0.41)
        case .modeShift: CGPoint(x: 0.75, y: 0.34)
        }
    }

    var title: String {
        switch self {
        case .middle: String(localized: "Middle Button")
        case .back: String(localized: "Back Button")
        case .forward: String(localized: "Forward Button")
        case .modeShift: String(localized: "Mode Shift Button")
        }
    }
}

/// An action assignable to a button.
enum MouseAction: String, CaseIterable, Identifiable, Codable {
    case `default`
    case none

    // Mouse buttons
    case leftClick
    case rightClick
    case middleClick
    case backClick
    case forwardClick

    // Editing
    case copy
    case paste
    case cut
    case undo
    case selectAll
    case save
    case find

    // Browser
    case browserBack
    case browserForward
    case newTab
    case closeTab
    case nextTab
    case prevTab

    // System
    case missionControl
    case appExpose
    case launchpad
    case spotlight
    case spaceLeft
    case spaceRight
    case screenshot

    // Media
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case nextTrack
    case prevTrack

    var id: String { rawValue }

    var category: Category {
        switch self {
        case .default, .none: .general
        case .leftClick, .rightClick, .middleClick, .backClick, .forwardClick: .mouse
        case .copy, .paste, .cut, .undo, .selectAll, .save, .find: .editing
        case .browserBack, .browserForward, .newTab, .closeTab, .nextTab, .prevTab: .browser
        case .missionControl, .appExpose, .launchpad, .spotlight, .spaceLeft, .spaceRight, .screenshot: .system
        case .volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .prevTrack: .media
        }
    }

    enum Category: String, CaseIterable {
        case general, mouse, editing, browser, system, media
    }

    /// Keyboard shortcut to synthesize, when applicable (default macOS shortcuts).
    var keyCombo: (flags: CGEventFlags, key: CGKeyCode)? {
        let cmd: CGEventFlags = .maskCommand
        let ctrl: CGEventFlags = .maskControl
        let ctrlShift: CGEventFlags = [.maskControl, .maskShift]
        let combo: (CGEventFlags, CGKeyCode)?
        switch self {
        case .copy: combo = (cmd, 0x08)
        case .paste: combo = (cmd, 0x09)
        case .cut: combo = (cmd, 0x07)
        case .undo: combo = (cmd, 0x06)
        case .selectAll: combo = (cmd, 0x00)
        case .save: combo = (cmd, 0x01)
        case .find: combo = (cmd, 0x03)
        case .browserBack: combo = (cmd, 0x21)
        case .browserForward: combo = (cmd, 0x1E)
        case .newTab: combo = (cmd, 0x11)
        case .closeTab: combo = (cmd, 0x0D)
        case .nextTab: combo = (ctrl, 0x30)
        case .prevTab: combo = (ctrlShift, 0x30)
        default: combo = nil
        }
        return combo
    }

    /// NX aux key for media actions.
    var mediaKey: Int32? {
        switch self {
        case .volumeUp: 0   // NX_KEYTYPE_SOUND_UP
        case .volumeDown: 1 // NX_KEYTYPE_SOUND_DOWN
        case .mute: 7       // NX_KEYTYPE_MUTE
        case .playPause: 16 // NX_KEYTYPE_PLAY
        case .nextTrack: 17 // NX_KEYTYPE_NEXT
        case .prevTrack: 18 // NX_KEYTYPE_PREVIOUS
        default: nil
        }
    }

    /// Mouse click to synthesize, when applicable (Quartz other-button number).
    var mouseClick: Int? {
        switch self {
        case .leftClick: 0
        case .rightClick: 1
        case .middleClick: 2
        case .backClick: 3
        case .forwardClick: 4
        default: nil
        }
    }

    var title: String {
        switch self {
        case .default: String(localized: "Default")
        case .none: String(localized: "Do Nothing")
        case .leftClick: String(localized: "Left Click")
        case .rightClick: String(localized: "Right Click")
        case .middleClick: String(localized: "Middle Click")
        case .backClick: String(localized: "Back")
        case .forwardClick: String(localized: "Forward")
        case .copy: String(localized: "Copy")
        case .paste: String(localized: "Paste")
        case .cut: String(localized: "Cut")
        case .undo: String(localized: "Undo")
        case .selectAll: String(localized: "Select All")
        case .save: String(localized: "Save")
        case .find: String(localized: "Find")
        case .browserBack: String(localized: "Browser Back")
        case .browserForward: String(localized: "Browser Forward")
        case .newTab: String(localized: "New Tab")
        case .closeTab: String(localized: "Close Tab")
        case .nextTab: String(localized: "Next Tab")
        case .prevTab: String(localized: "Previous Tab")
        case .missionControl: String(localized: "Mission Control")
        case .appExpose: String(localized: "App Exposé")
        case .launchpad: String(localized: "Launchpad")
        case .spotlight: String(localized: "Spotlight")
        case .spaceLeft: String(localized: "Desktop Left")
        case .spaceRight: String(localized: "Desktop Right")
        case .screenshot: String(localized: "Screenshot")
        case .volumeUp: String(localized: "Volume Up")
        case .volumeDown: String(localized: "Volume Down")
        case .mute: String(localized: "Mute")
        case .playPause: String(localized: "Play / Pause")
        case .nextTrack: String(localized: "Next Track")
        case .prevTrack: String(localized: "Previous Track")
        }
    }
}

extension MouseAction.Category {
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .mouse: String(localized: "Mouse")
        case .editing: String(localized: "Editing")
        case .browser: String(localized: "Browser")
        case .system: String(localized: "System")
        case .media: String(localized: "Media")
        }
    }
}
