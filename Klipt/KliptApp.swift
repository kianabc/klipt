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
    private var panel: NSPanel?
    private var pastePickerPanel: PastePickerPanel?
    private var store = ClipboardStore()
    private var settings = KliptSettings.shared
    private var clipboardMonitor: ClipboardMonitor!
    private var screenshotService: ScreenshotService!
    private var dragTrayWindow: DragTrayWindow!
    private var statusItem: NSStatusItem?
    private var isVisible = false
    private var flashTimer: Timer?
    private var expirationTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardMonitor = ClipboardMonitor(store: store)
        screenshotService = ScreenshotService(store: store)
        dragTrayWindow = DragTrayWindow(store: store)

        setupStatusBar()
        setupPanel()
        setupPastePicker()
        setupHotkeys()
        clipboardMonitor.start()
        screenshotService.start()
        dragTrayWindow.startMonitoring()

        // Purge expired items once per hour
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.store.purgeExpired()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(hidePanel), name: .hideKliptPanel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(togglePanel), name: .toggleKliptPanel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onItemAdded), name: .itemAdded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hidePastePicker), name: .hidePastePicker, object: nil)
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Klipt")
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    private func setupPanel() {
        let contentView = KliptPanel(
            store: store,
            clipboardMonitor: clipboardMonitor,
            settings: settings,
            onShortcutsChanged: {
                HotkeyManager.shared.reregister()
            }
        )
        .overlay(DropTargetView(store: store))

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 520)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false

        self.panel = panel
    }

    private func setupPastePicker() {
        pastePickerPanel = PastePickerPanel(store: store, clipboardMonitor: clipboardMonitor)
    }

    private func setupHotkeys() {
        HotkeyManager.shared.register(
            onToggle: { [weak self] in
                DispatchQueue.main.async {
                    self?.togglePanel()
                }
            },
            onPastePicker: { [weak self] in
                DispatchQueue.main.async {
                    self?.showPastePicker()
                }
            }
        )
    }

    @objc func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel = panel else { return }
        if let screenFrame = NSScreen.main?.visibleFrame {
            let x = screenFrame.maxX - panel.frame.width - 16
            let y = screenFrame.maxY - panel.frame.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    @objc func hidePanel() {
        flashTimer?.invalidate()
        flashTimer = nil
        panel?.orderOut(nil)
        isVisible = false
    }

    private func showPastePicker() {
        pastePickerPanel?.showCentered()
    }

    @objc func hidePastePicker() {
        pastePickerPanel?.orderOut(nil)
    }

    @objc func onItemAdded() {
        flashTimer?.invalidate()

        if !isVisible {
            showPanel()
            flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.hidePanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        screenshotService.stop()
        dragTrayWindow.stopMonitoring()
        HotkeyManager.shared.unregister()
        expirationTimer?.invalidate()
    }
}
