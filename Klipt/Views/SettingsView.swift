import SwiftUI
import Carbon

struct SettingsView: View {
    @Bindable var settings: KliptSettings
    let onShortcutsChanged: () -> Void

    @State private var recordingToggle = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section("Shortcut") {
                    ShortcutRecorderRow(
                        label: "Toggle Klipt",
                        displayString: settings.toggleShortcutDisplayString,
                        isRecording: $recordingToggle,
                        onRecord: { keyCode, modifiers in
                            settings.toggleShortcutKeyCode = keyCode
                            settings.toggleShortcutModifiers = modifiers
                            onShortcutsChanged()
                        }
                    )
                }

                Section("Screenshots") {
                    Text("Klipt automatically captures all screenshots.")
                        .font(.callout)
                    Text("Use your normal shortcuts — \u{2318}\u{21E7}3, \u{2318}\u{21E7}4, \u{2318}\u{21E7}5 — and screenshots will go straight to Klipt instead of your Desktop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Expiration") {
                    HStack {
                        Text("Auto-delete after")
                        Spacer()
                        Picker("", selection: $settings.expirationDays) {
                            Text("1 day").tag(1)
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                        }
                        .frame(width: 120)
                    }

                    Text("Pinned items never expire.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 380, height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ShortcutRecorderRow: View {
    let label: String
    let displayString: String
    @Binding var isRecording: Bool
    let onRecord: (UInt32, UInt32) -> Void

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if isRecording {
                ShortcutRecorder(onRecord: { keyCode, modifiers in
                    onRecord(keyCode, modifiers)
                    isRecording = false
                })
                .frame(width: 120, height: 24)
            } else {
                Button(action: { isRecording = true }) {
                    Text(displayString)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}
}

class ShortcutRecorderNSView: NSView {
    var onRecord: ((UInt32, UInt32) -> Void)?
    private let label = NSTextField(labelWithString: "Press keys...")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        var carbonMods: UInt32 = 0
        if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }

        if carbonMods != 0 {
            onRecord?(UInt32(event.keyCode), carbonMods)
        }
    }
}
