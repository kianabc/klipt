import Carbon
import AppKit

class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var onToggle: (() -> Void)?
    private var handlerInstalled = false

    static let shared = HotkeyManager()

    func register(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        if !handlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

                if hotKeyID.id == 1 {
                    HotkeyManager.shared.onToggle?()
                }
                return noErr
            }, 1, &eventType, nil, nil)
            handlerInstalled = true
        }

        registerKeys()
    }

    func reregister() {
        unregisterKeys()
        registerKeys()
    }

    private func registerKeys() {
        let settings = KliptSettings.shared
        let hotkeyID = EventHotKeyID(signature: OSType(0x4B4C5054), id: 1)
        RegisterEventHotKey(settings.shortcutKeyCode, settings.shortcutModifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    private func unregisterKeys() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    func unregister() {
        unregisterKeys()
    }

    deinit {
        unregister()
    }
}
