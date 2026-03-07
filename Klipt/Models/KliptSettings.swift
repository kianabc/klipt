import Foundation
import Carbon

@Observable
class KliptSettings {
    static let shared = KliptSettings()

    var expirationDays: Int {
        didSet { UserDefaults.standard.set(expirationDays, forKey: "klipt_expirationDays") }
    }

    var toggleShortcutKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(toggleShortcutKeyCode, forKey: "klipt_toggleKeyCode") }
    }

    var toggleShortcutModifiers: UInt32 {
        didSet { UserDefaults.standard.set(toggleShortcutModifiers, forKey: "klipt_toggleModifiers") }
    }

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "klipt_expirationDays") != nil {
            self.expirationDays = defaults.integer(forKey: "klipt_expirationDays")
        } else {
            self.expirationDays = 30
        }

        if defaults.object(forKey: "klipt_toggleKeyCode") != nil {
            self.toggleShortcutKeyCode = UInt32(defaults.integer(forKey: "klipt_toggleKeyCode"))
            self.toggleShortcutModifiers = UInt32(defaults.integer(forKey: "klipt_toggleModifiers"))
        } else {
            self.toggleShortcutKeyCode = UInt32(kVK_ANSI_K)
            self.toggleShortcutModifiers = UInt32(cmdKey | shiftKey)
        }
    }

    var toggleShortcutDisplayString: String {
        modifierString(toggleShortcutModifiers) + keyString(toggleShortcutKeyCode)
    }

    private func modifierString(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "^" }
        if mods & UInt32(optionKey) != 0 { s += "\u{2325}" }
        if mods & UInt32(shiftKey) != 0 { s += "\u{21E7}" }
        if mods & UInt32(cmdKey) != 0 { s += "\u{2318}" }
        return s
    }

    private func keyString(_ keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
        ]
        return keyMap[keyCode] ?? "?"
    }
}
