import AppKit

/// Release notes rendered rather than shown as raw markdown.
///
/// `NSAlert.informativeText` is plain text, so markdown put there shows its
/// asterisks. The notes go in an accessory text view instead, through
/// `.inlineOnlyPreservingWhitespace` so `**bold**` is bold and `- ` becomes a
/// bullet.
@MainActor
enum ReleaseNotesView {
    static func make(markdown: String) -> NSView {
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 2)

        let rendered: NSAttributedString = {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)
            guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
                return NSAttributedString(string: markdown)
            }
            let attributed = NSMutableAttributedString(parsed)
            attributed.addAttributes(
                [.foregroundColor: NSColor.labelColor],
                range: NSRange(location: 0, length: attributed.length))
            return attributed
        }()
        text.textStorage?.setAttributedString(rendered)
        text.font = .systemFont(ofSize: 12)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 180))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = text
        text.frame = NSRect(x: 0, y: 0, width: 380, height: 180)
        text.autoresizingMask = [.width]
        return scroll
    }
}

/// The alert that offers an update.
@MainActor
enum UpdateOfferAlert {
    /// Returns true if the user chose to update.
    static func ask(version: String, notes: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Klipt \(version) is available"
        alert.informativeText = "Here's what's changed since your version."
        alert.accessoryView = ReleaseNotesView.make(markdown: notes)
        alert.addButton(withTitle: "Update and Restart")
        alert.addButton(withTitle: "Later")
        // Klipt is LSUIElement. Without this the alert opens behind whatever
        // the user is actually looking at and reads as nothing happening.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// A small window saying what the updater is doing.
///
/// Download, verify and hand-over take several seconds with nothing visible.
/// Silent seconds read as a hang, and a hang during an update is the one thing
/// that makes people force-quit — which is the one thing that would break it.
@MainActor
final class UpdateProgressWindow {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(version: String) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 96))

        let title = NSTextField(labelWithString: "Updating Klipt to \(version)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 20, y: 62, width: 340, height: 18)

        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 42, width: 340, height: 16)

        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0
        bar.maxValue = 1
        bar.frame = NSRect(x: 20, y: 18, width: 340, height: 20)
        bar.startAnimation(nil)

        content.addSubview(title)
        content.addSubview(label)
        content.addSubview(bar)

        window = NSWindow(contentRect: content.frame, styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.contentView = content
        window.title = "Klipt"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
    }

    func show(_ progress: UpdateProgress) {
        label.stringValue = progress.phase
        if let fraction = progress.fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func close() { window.orderOut(nil) }
}

/// Check → offer → stage → relaunch, and every way that can go wrong.
@MainActor
final class UpdateCoordinator {
    static let shared = UpdateCoordinator()
    private init() {}

    private var busy = false
    /// Set by the app: true when showing a modal offer would interrupt
    /// something. Checked at the moment of offering, not of checking.
    var shouldDefer: (() -> Bool)?
    private var retryTimer: Timer?

    /// Launch path. Silent unless something is actually available, so a normal
    /// start never shows anything.
    func checkIfDue() {
        guard UpdatePreference.isDue else { return }
        Task { await run(userInitiated: false) }
    }

    /// Menu item and the Settings button. Always reports an outcome, because a
    /// button that does nothing visible reads as broken.
    func checkNow() {
        Task { await run(userInitiated: true) }
    }

    private func run(userInitiated: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        do {
            NSLog("Klipt update check: looking")
            let update = try await UpdateChecker().check()
            // Only on success: a failed check must not push the next one a
            // day away, or a laptop that was offline at the wrong moment
            // stops hearing about releases.
            UpdatePreference.lastChecked = Date()
            guard let update else {
                NSLog("Klipt update check: up to date on \(currentVersion)")
                if userInitiated { inform("Klipt is up to date.", "You're on \(currentVersion).") }
                return
            }
            NSLog("Klipt update available: \(update.version)")

            // A background offer waits for a better moment; one the user asked
            // for is shown regardless, since they are already looking at us.
            if !userInitiated, shouldDefer?() == true {
                NSLog("Klipt update: deferring the offer, the tray is open")
                scheduleRetry()
                return
            }
            guard UpdateOfferAlert.ask(version: "\(update.version)",
                                       notes: update.releaseNotes) else { return }
            await install(update)
        } catch {
            NSLog("Klipt update check failed: \(error.localizedDescription)")
            if userInitiated {
                inform("Couldn't check for updates", error.localizedDescription)
            }
        }
    }

    /// Try again shortly rather than waiting for the next hourly tick: the
    /// tray is usually only open for a few seconds.
    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            MainActor.assumeIsolated { UpdateCoordinator.shared.checkIfDue() }
        }
    }

    private func install(_ update: AvailableUpdate) async {
        let progress = UpdateProgressWindow(version: "\(update.version)")
        progress.show(UpdateProgress("Starting…"))
        do {
            let staged = try await Updater().stage(update) { step in
                Task { @MainActor in progress.show(step) }
            }
            try Updater.relaunch(with: staged)
        } catch {
            progress.close()
            NSLog("Klipt update failed: \(error.localizedDescription)")
            // Say plainly that nothing was touched. A failed update is alarming
            // precisely because people assume it left the app half-replaced.
            let alert = NSAlert()
            alert.messageText = "Update failed"
            alert.informativeText = """
            \(error.localizedDescription)

            Klipt is still running and unchanged. You can download the update \
            yourself instead.
            """
            alert.addButton(withTitle: "Open Releases")
            alert.addButton(withTitle: "Close")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(update.pageURL)
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "an unknown build"
    }

    private func inform(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
