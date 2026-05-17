import Carbon
import Foundation

final class HotkeyManager {
    enum Action: UInt32 {
        case grammar = 1
        case clipboard = 2
    }

    private var registeredHotkeys: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    var onGrammar: (() -> Void)?
    var onClipboard: (() -> Void)?

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handler {
            RemoveEventHandler(handler)
        }
    }

    func register(grammar: Hotkey, clipboard: Hotkey) {
        unregisterAll()
        register(hotkey: grammar, action: .grammar)
        register(hotkey: clipboard, action: .clipboard)
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hotkeyID.id {
                case Action.grammar.rawValue:
                    manager.onGrammar?()
                case Action.clipboard.rawValue:
                    manager.onClipboard?()
                default:
                    break
                }
            }
            return noErr
        }, 1, &eventType, selfPointer, &handler)
    }

    private func register(hotkey: Hotkey, action: Action) {
        var hotkeyRef: EventHotKeyRef?
        var hotkeyID = EventHotKeyID(signature: fourCharCode("Tidy"), id: action.rawValue)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        if status == noErr {
            registeredHotkeys.append(hotkeyRef)
        }
    }

    private func unregisterAll() {
        for hotkey in registeredHotkeys {
            if let hotkey {
                UnregisterEventHotKey(hotkey)
            }
        }
        registeredHotkeys.removeAll()
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
