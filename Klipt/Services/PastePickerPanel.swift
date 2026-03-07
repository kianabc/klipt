import AppKit
import SwiftUI

class PastePickerPanel: NSPanel {
    private var pickerView: PastePickerView?
    private var hostingView: NSHostingView<PastePickerView>?

    init(store: ClipboardStore, clipboardMonitor: ClipboardMonitor) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        let picker = PastePickerView(store: store, clipboardMonitor: clipboardMonitor)
        self.pickerView = picker

        let hosting = NSHostingView(rootView: picker)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        self.hostingView = hosting

        self.contentView = hosting
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.animationBehavior = .utilityWindow
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = true
    }

    func showCentered() {
        // Reset state
        pickerView?.selectedTab = .all
        pickerView?.selectedIndex = 0
        updateHostingView()

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.midY - frame.height / 2 + 60
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 126: // Up arrow
            pickerView?.moveUp()
            updateHostingView()
        case 125: // Down arrow
            pickerView?.moveDown()
            updateHostingView()
        case 123: // Left arrow — previous tab
            switchTab(direction: -1)
        case 124: // Right arrow — next tab
            switchTab(direction: 1)
        case 36: // Return — confirm
            pickerView?.confirmSelection()
        case 53: // Escape — cancel
            pickerView?.cancel()
        default:
            super.keyDown(with: event)
        }
    }

    private func switchTab(direction: Int) {
        guard let current = pickerView?.selectedTab else { return }
        let tabs = PastePickerTab.allCases
        guard let idx = tabs.firstIndex(of: current) else { return }
        let newIdx = (idx + direction + tabs.count) % tabs.count
        pickerView?.selectedTab = tabs[newIdx]
        pickerView?.selectedIndex = 0
        updateHostingView()
    }

    private func updateHostingView() {
        guard let picker = pickerView else { return }
        hostingView?.rootView = picker
    }
}
