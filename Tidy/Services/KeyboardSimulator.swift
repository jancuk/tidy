import AppKit
import Carbon

enum KeyboardSimulator {
    static func sendCommandKey(_ virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    static func copy() {
        sendCommandKey(CGKeyCode(kVK_ANSI_C))
    }

    static func paste() {
        sendCommandKey(CGKeyCode(kVK_ANSI_V))
    }
}
