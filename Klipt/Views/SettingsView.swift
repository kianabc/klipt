import SwiftUI
import Carbon
import Sparkle

struct SettingsView: View {
    @Bindable var settings: KliptSettings
    let onShortcutsChanged: () -> Void

    @State private var recordingShortcut = false
    @State private var showResetConfirmation = false
    @State private var licenseKeyInput = ""

    private var license: LicenseManager { LicenseManager.shared }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                // Unlock / License
                if !license.isLicensed {
                    unlockCard
                } else {
                    licensedCard
                }

                // Shortcut
                settingsCard {
                    HStack {
                        Label {
                            Text("Open Klipt")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.85))
                        } icon: {
                            Image(systemName: "keyboard")
                                .font(.system(size: 12))
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        if recordingShortcut {
                            ShortcutRecorder(onRecord: { keyCode, modifiers in
                                settings.shortcutKeyCode = keyCode
                                settings.shortcutModifiers = modifiers
                                onShortcutsChanged()
                                recordingShortcut = false
                            })
                            .frame(width: 120, height: 28)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        } else {
                            Button(action: { recordingShortcut = true }) {
                                Text(settings.shortcutDisplayString)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Expiration
                settingsCard {
                    HStack {
                        Label {
                            Text("Auto-delete after")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.85))
                        } icon: {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        if license.isLicensed {
                            Picker("", selection: $settings.expirationDays) {
                                Text("1 day").tag(1)
                                Text("3 days").tag(3)
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                            }
                            .frame(width: 110)
                        } else {
                            Text("1 day")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.4))
                        }
                    }
                    if license.isLicensed {
                        Text("Pinned items never expire.")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.3))
                            .padding(.leading, 24)
                    } else {
                        Text("Unlock to keep history up to 30 days. Pinned items never expire.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange.opacity(0.6))
                            .padding(.leading, 24)
                    }
                }

                // Reset
                settingsCard {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clear history")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary.opacity(0.85))
                                Text("Pinned items will be kept")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary.opacity(0.35))
                            }
                        } icon: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        Spacer()
                        Button("Reset") {
                            showResetConfirmation = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }

                // Updates
                settingsCard {
                    HStack {
                        Label {
                            Text("Software Update")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.85))
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("Check for Updates") {
                            UpdaterService.shared.checkForUpdates()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }

                // About
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Klipt")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.primary.opacity(0.35))
                            }
                            Spacer()
                        }
                        Divider().opacity(0.1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your clipboard, but better.")
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.5))
                            Text("By Kian Torimi")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.5))
                            Text("klipt.app")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                        Divider().opacity(0.1)
                        Button(action: {
                            if let url = URL(string: "https://klipt.app/changelog") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                Text("View Changelog")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.blue.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clear clipboard history?", isPresented: $showResetConfirmation) {
            Button("Clear", role: .destructive) {
                NotificationCenter.default.post(name: .clearUnpinned, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all items except pinned ones.")
        }
    }

    // MARK: - Unlock card (not licensed)

    private var unlockCard: some View {
        settingsCard {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Klipt")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Keep clipboard history up to 30 days")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                    Spacer()
                    Text("$3")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.yellow)
                }

                // Buy button
                Button(action: {
                    // TODO: Replace with your LemonSqueezy checkout URL
                    if let url = URL(string: "https://kliptapp.lemonsqueezy.com/checkout/buy/49253fd2-f7b1-4193-9f95-6c5168aa361a") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Buy License")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Divider().opacity(0.1)

                // License key input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Already have a key?")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.35))
                    HStack(spacing: 8) {
                        TextField("Enter license key", text: $licenseKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Button(action: {
                            license.validate(key: licenseKeyInput)
                        }) {
                            if license.isValidating {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 60, height: 28)
                            } else {
                                Text("Activate")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .frame(width: 60, height: 28)
                            }
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .disabled(licenseKeyInput.isEmpty || license.isValidating)
                    }
                    if let error = license.validationError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
            }
        }
    }

    // MARK: - Licensed card

    private var licensedCard: some View {
        settingsCard {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Klipt Unlocked")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Thank you for your support!")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.4))
                }
                Spacer()
            }
        }
    }

    // MARK: - Card helper

    private func settingsCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
