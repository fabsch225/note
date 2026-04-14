import Carbon
import Foundation

struct HotKeyModifiers: OptionSet {
    let rawValue: UInt32

    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let option = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let shift = HotKeyModifiers(rawValue: UInt32(shiftKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
}

final class HotKeyManager {
    private let keyCode: UInt32
    private let modifiers: HotKeyModifiers
    private let onHotKey: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: HotKeyModifiers, onHotKey: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onHotKey = onHotKey
    }

    func start() {
        stop()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotKey()
            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &handlerRef)

        // 'NPOP'
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E504F50), id: 1)
        RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        stop()
    }
}
