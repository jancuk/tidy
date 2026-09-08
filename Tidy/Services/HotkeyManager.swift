import Carbon
import Foundation

final class HotkeyManager {
    enum Action: UInt32 {
        case grammar = 1
        case clipboard = 2
        case askAI = 3
        case textActions = 4
        case capture = 5
    }

    private var registeredHotkeys: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    var onGrammar: (() -> Void)?
    var onClipboard: (() -> Void)?
    var onAskAI: (() -> Void)?
    var onTextActions: (() -> Void)?
    var onCapture: (() -> Void)?
    var onCustomAction: ((String) -> Void)?
    private var customIDs: [UInt32: String] = [:]
    private(set) var registrationErrors: [String] = []

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handler {
            RemoveEventHandler(handler)
        }
    }

    func register(grammar: Hotkey, clipboard: Hotkey, askAI: Hotkey, textActions: Hotkey = .textActionsDefault, capture: Hotkey = .captureDefault, custom: [TextAction] = []) {
        unregisterAll()
        customIDs.removeAll()
        registrationErrors.removeAll()
        register(hotkey: grammar, action: .grammar)
        register(hotkey: clipboard, action: .clipboard)
        register(hotkey: askAI, action: .askAI)
        register(hotkey: textActions, action: .textActions)
        register(hotkey: capture, action: .capture)
        for (index, action) in custom.enumerated() {
            guard let raw = action.shortcut, !raw.isEmpty, let key = Hotkey.validated(raw) else { continue }
            let id = UInt32(index + 100)
            customIDs[id] = action.id
            register(hotkey: key, id: id)
        }
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
                case Action.askAI.rawValue:
                    manager.onAskAI?()
                case Action.textActions.rawValue: manager.onTextActions?()
                case Action.capture.rawValue: manager.onCapture?()
                default:
                    if let id = manager.customIDs[hotkeyID.id] { manager.onCustomAction?(id) }
                }
            }
            return noErr
        }, 1, &eventType, selfPointer, &handler)
    }

    private func register(hotkey: Hotkey, action: Action) {
        register(hotkey: hotkey, id: action.rawValue)
    }

    private func register(hotkey: Hotkey, id: UInt32) {
        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: fourCharCode("Tidy"), id: id)
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
        } else {
            registrationErrors.append("Could not register \(hotkey.displayValue). It may already be in use.")
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
