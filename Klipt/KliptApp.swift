import SwiftUI
import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        showOnboardingIfNeeded()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Klipt")?.withSymbolConfiguration(config)
            button.image = image
        }

        let menu = NSMenu()
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

    @objc func toggleKlipt() {
        guard let panel = kliptPanel else { return }
        if panel.isVisible {
            panel.dismiss()
        } else {
            panel.showCentered()
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
            flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
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
