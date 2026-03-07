import Carbon
import AppKit

class HotkeyManager {
    private var toggleHotkeyRef: EventHotKeyRef?
    private var pastePickerHotkeyRef: EventHotKeyRef?
    private var onToggle: (() -> Void)?
    private var onPastePicker: (() -> Void)?
    private var handlerInstalled = false

    static let shared = HotkeyManager()

    func register(onToggle: @escaping () -> Void, onPastePicker: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onPastePicker = onPastePicker

        if !handlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

                switch hotKeyID.id {
                case 1:
                    HotkeyManager.shared.onToggle?()
                case 2:
                    HotkeyManager.shared.onPastePicker?()
                default:
                    break
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

        // Toggle panel — configurable
        var toggleID = EventHotKeyID(signature: OSType(0x4B4C5054), id: 1)
        RegisterEventHotKey(settings.toggleShortcutKeyCode, settings.toggleShortcutModifiers, toggleID, GetApplicationEventTarget(), 0, &toggleHotkeyRef)

        // Paste picker — CMD+SHIFT+V (fixed)
        var pasteID = EventHotKeyID(signature: OSType(0x4B4C5054), id: 2)
        let vKey: UInt32 = UInt32(kVK_ANSI_V)
        let mods: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(vKey, mods, pasteID, GetApplicationEventTarget(), 0, &pastePickerHotkeyRef)
    }

    private func unregisterKeys() {
        if let ref = toggleHotkeyRef {
            UnregisterEventHotKey(ref)
            toggleHotkeyRef = nil
        }
        if let ref = pastePickerHotkeyRef {
            UnregisterEventHotKey(ref)
            pastePickerHotkeyRef = nil
        }
    }

    func unregister() {
        unregisterKeys()
    }

    deinit {
        unregister()
    }
}
