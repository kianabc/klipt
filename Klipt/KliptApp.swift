import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "app.klipt.Klipt", category: "App")

@main
struct KliptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var kliptPanel: KliptPanel?
    private var onboardingWindow: OnboardingWindow?
    private var store = ClipboardStore()
    private var settings = KliptSettings.shared
    private var clipboardMonitor: ClipboardMonitor!
    private var screenshotService: ScreenshotService!
    private var dragMonitor: DragMonitor!
    private var statusItem: NSStatusItem?
    private var flashTimer: Timer?
    private var expirationTimer: Timer?
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable App Nap and Automatic Termination
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .idleSystemSleepDisabled],
            reason: "Klipt needs to respond to global hotkeys and monitor clipboard"
        )
        ProcessInfo.processInfo.disableAutomaticTermination("Klipt must remain running for hotkeys and clipboard monitoring")
        ProcessInfo.processInfo.disableSuddenTermination()
        logger.info("Klipt launched, automatic termination disabled")

        clipboardMonitor = ClipboardMonitor(store: store)
        screenshotService = ScreenshotService(store: store)

        _ = UpdaterService.shared // Initialize Sparkle updater
        setupStatusBar()
        setupPanel()
        setupHotkeys()
        setupDragMonitor()
        clipboardMonitor.start()
        screenshotService.start()

        expirationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.store.purgeExpired()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(hideKlipt), name: .hideKlipt, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onItemAdded), name: .itemAdded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clearUnpinned), name: .clearUnpinned, object: nil)

        cleanupTempFiles()
        showOnboardingIfNeeded()
    }

    private func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("KliptDrag")
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Klipt")?.withSymbolConfiguration(config)
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Klipt", action: #selector(showKlipt), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Klipt", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        kliptPanel?.showSettings()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func setupPanel() {
        kliptPanel = KliptPanel(
            store: store,
            clipboardMonitor: clipboardMonitor,
            settings: settings,
            onShortcutsChanged: {
                HotkeyManager.shared.reregister()
            }
        )
    }

    private func setupDragMonitor() {
        guard let panel = kliptPanel else { return }
        dragMonitor = DragMonitor(panel: panel)
        dragMonitor.startMonitoring()
    }

    private func setupHotkeys() {
        HotkeyManager.shared.register(
            onToggle: { [weak self] in
                DispatchQueue.main.async {
                    self?.toggleKlipt()
                }
            }
        )
    }

    @objc func showKlipt() {
        flashTimer?.invalidate()
        flashTimer = nil
        guard let panel = kliptPanel else { return }
        kliptLog("showKlipt: isVisible=\(panel.isVisible)")
        panel.showCentered()
    }

    @objc func toggleKlipt() {
        flashTimer?.invalidate()
        flashTimer = nil
        guard let panel = kliptPanel else { return }
        kliptLog("toggleKlipt: isVisible=\(panel.isVisible)")
        if panel.isVisible {
            panel.dismiss()
        } else {
            panel.showCentered()
        }
    }

    func kliptLog(_ message: String) {
        AppDelegate.log(message)
    }

    static func log(_ message: String) {
        let logDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Klipt", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("klipt.log")
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    @objc func hideKlipt() {
        kliptPanel?.dismiss()
    }

    @objc func clearUnpinned() {
        store.clearUnpinned()
    }

    @objc func onItemAdded() {
        flashTimer?.invalidate()

        guard let panel = kliptPanel else { return }

        if panel.isVisible {
            // Panel already showing — just switch to latest item
            panel.resetToLatest()
        } else {
            // Flash the panel briefly to show the new item
            panel.showCentered()
            flashTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.hideKlipt()
            }
        }
    }

    private func showOnboardingIfNeeded() {
        let key = "hasCompletedOnboarding"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let window = OnboardingWindow {
            UserDefaults.standard.set(true, forKey: key)
        }
        window.showCentered()
        self.onboardingWindow = window
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        screenshotService.stop()
        dragMonitor.stopMonitoring()
        HotkeyManager.shared.unregister()
        expirationTimer?.invalidate()
    }
}
