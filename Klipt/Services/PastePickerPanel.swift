import AppKit
import SwiftUI
import UniformTypeIdentifiers

class KliptPanel: NSPanel {
    private let store: ClipboardStore
    private let clipboardMonitor: ClipboardMonitor
    private let settings: KliptSettings
    private let kliptState = KliptState()
    private var clickOutsideMonitor: Any?
    private var hostingView: NSHostingView<KliptMainView>?
    private var dropTargetView: KliptDropTargetView?
    private var wasExpandedBeforeSettings = false
    private var ignoreClickOutside = false
    var openedForDrag = false

    private let minCompactHeight: CGFloat = 340
    private let maxCompactHeight: CGFloat = 680
    private let settingsHeight: CGFloat = 740
    private let panelWidth: CGFloat = 480
    /// Chrome around the image: top bar (~55) + padding (16) + timestamp (~25) + counter (~35) + bottom bar (~45)
    private let chromeHeight: CGFloat = 176

    override var canBecomeKey: Bool { true }

    init(store: ClipboardStore, clipboardMonitor: ClipboardMonitor, settings: KliptSettings, onShortcutsChanged: @escaping () -> Void) {
        self.store = store
        self.clipboardMonitor = clipboardMonitor
        self.settings = settings

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let view = KliptMainView(
            store: store,
            clipboardMonitor: clipboardMonitor,
            settings: settings,
            state: kliptState,
            onConfirm: { [weak self] in self?.confirmSelection() },
            onTogglePin: { [weak self] in self?.togglePin() },
            onToggleExpand: { [weak self] in self?.toggleExpand() },
            onShortcutsChanged: onShortcutsChanged
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 340)
        self.hostingView = hosting

        // Add drop target overlay on top of hosting view
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let drop = KliptDropTargetView(store: store)
        drop.frame = container.bounds
        drop.autoresizingMask = [.width, .height]
        container.addSubview(drop)
        self.dropTargetView = drop

        self.contentView = container

        kliptState.onSelectionChanged = { [weak self] in
            guard let self = self, self.isVisible, !self.kliptState.isExpanded, self.kliptState.selectedTab != .settings else { return }
            self.resizePanel(animated: true)
        }

        kliptState.onTabChanged = { [weak self] tab in
            guard let self = self, self.isVisible else { return }
            if tab == .settings {
                self.wasExpandedBeforeSettings = self.kliptState.isExpanded
                self.kliptState.isExpanded = false
                self.resizePanel(animated: true)
            } else {
                if !self.wasExpandedBeforeSettings {
                    self.kliptState.isExpanded = false
                }
                self.resizePanel(animated: true)
            }
        }

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isMovable = true
        self.isMovableByWindowBackground = true
    }

    func showCentered() {
        openedForDrag = false
        kliptState.restore()
        kliptState.isDragMode = false
        positionPanel()
        makeKeyAndOrderFront(nil)
        startClickOutsideMonitor()
    }

    func showForDrag() {
        guard !isVisible else { return }
        openedForDrag = true
        kliptState.reset()
        kliptState.isDragMode = true
        positionPanel()
        orderFront(nil)
    }

    func resetToLatest() {
        kliptState.reset()
        resizePanel(animated: true)
    }

    func showSettings() {
        kliptState.selectedTab = .settings
        kliptState.isDragMode = false
        positionPanel()
        makeKeyAndOrderFront(nil)
        startClickOutsideMonitor()
    }

    func dismiss() {
        stopClickOutsideMonitor()
        savePosition()
        orderOut(nil)
    }

    private func savePosition() {
        // Save X and top edge (origin.y + height) so position is stable regardless of panel height
        UserDefaults.standard.set(frame.origin.x, forKey: "klipt_windowX")
        UserDefaults.standard.set(frame.origin.y + frame.size.height, forKey: "klipt_windowTop")
        UserDefaults.standard.set(true, forKey: "klipt_hasPosition")
    }

    func toggleExpand() {
        kliptState.isExpanded.toggle()
        ignoreClickOutside = true
        resizePanel(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.ignoreClickOutside = false
        }
    }

    private func expandedHeight() -> CGFloat {
        guard let screen = NSScreen.main else { return 600 }
        return screen.visibleFrame.height * 0.8
    }

    private func currentHeight() -> CGFloat {
        if kliptState.selectedTab == .settings {
            return settingsHeight
        }
        if kliptState.isExpanded {
            return expandedHeight()
        }
        return minCompactHeightForCurrentItem()
    }

    private func minCompactHeightForCurrentItem() -> CGFloat {
        let items = currentItems()
        guard !items.isEmpty else { return minCompactHeight }
        let item = items[min(kliptState.selectedIndex, items.count - 1)]

        if item.type == .image, let image = item.nsImage, image.size.height > 0 {
            let availableWidth = panelWidth - 20
            let aspectRatio = image.size.width / image.size.height
            let imageHeight = availableWidth / aspectRatio
            let totalHeight = imageHeight + chromeHeight
            return min(max(totalHeight, minCompactHeight), maxCompactHeight)
        }

        if item.type == .file {
            // Files get a taller panel to show the thumbnail preview + filename
            return min(minCompactHeight + 200, maxCompactHeight)
        }

        return minCompactHeight
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let height = currentHeight()

        let x: CGFloat
        let y: CGFloat

        if UserDefaults.standard.bool(forKey: "klipt_hasPosition") {
            let savedX = UserDefaults.standard.double(forKey: "klipt_windowX")
            let savedTop = UserDefaults.standard.double(forKey: "klipt_windowTop")

            // Validate saved position is within visible screen bounds
            if screenFrame.contains(NSPoint(x: savedX + panelWidth / 2, y: savedTop - height / 2)) {
                x = savedX
                y = savedTop - height
            } else {
                x = screenFrame.midX - panelWidth / 2
                y = screenFrame.midY - height / 2
            }
        } else {
            x = screenFrame.midX - panelWidth / 2
            y = screenFrame.midY - height / 2
        }

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: true)
        hostingView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
    }

    private func resizePanel(animated: Bool) {
        let height = currentHeight()
        // Keep current X and top edge, grow/shrink downward
        let topEdge = frame.origin.y + frame.size.height
        let x = frame.origin.x
        let y = topEdge - height
        let newFrame = NSRect(x: x, y: y, width: panelWidth, height: height)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
            // Update hosting view after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                guard let self = self else { return }
                self.hostingView?.frame = NSRect(x: 0, y: 0, width: self.panelWidth, height: height)
            }
        } else {
            setFrame(newFrame, display: true)
            hostingView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        }
    }

    // Handle all keyboard input directly on the panel
    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 126: // Up
            moveUp()
        case 125: // Down
            moveDown()
        case 123: // Left
            switchTab(direction: -1)
        case 124: // Right
            switchTab(direction: 1)
        case 36: // Return
            confirmSelection()
        case 53: // Escape
            cancel()
        case 49: // Space — toggle preview
            togglePreview()
        case 35: // P — toggle pin
            togglePin()
        case 48: // Tab — toggle expand
            toggleExpand()
        case 51: // Delete — remove item
            deleteSelected()
        default:
            super.keyDown(with: event)
        }
    }

    private func moveUp() {
        let items = currentItems()
        guard !items.isEmpty else { return }
        kliptState.selectedIndex = max(0, kliptState.selectedIndex - 1)
    }

    private func moveDown() {
        let items = currentItems()
        guard !items.isEmpty else { return }
        kliptState.selectedIndex = min(items.count - 1, kliptState.selectedIndex + 1)
    }

    private func switchTab(direction: Int) {
        let tabs = KliptTab.allCases
        guard let idx = tabs.firstIndex(of: kliptState.selectedTab) else { return }
        let newIdx = (idx + direction + tabs.count) % tabs.count
        kliptState.selectedTab = tabs[newIdx]
        kliptState.selectedIndex = 0
    }

    private func confirmSelection() {
        let items = currentItems()
        guard !items.isEmpty else { return }
        let item = items[min(kliptState.selectedIndex, items.count - 1)]
        clipboardMonitor.copyToClipboard(item)
        store.moveToTop(item)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            simulatePaste()
        }
    }

    private func togglePreview() {
        let items = currentItems()
        guard !items.isEmpty else { return }
        let item = items[min(kliptState.selectedIndex, items.count - 1)]
        setupPreviewNavigation()
        PreviewPanel.shared.toggle(item: item)
    }

    private func togglePin() {
        let items = currentItems()
        guard !items.isEmpty else { return }
        let item = items[min(kliptState.selectedIndex, items.count - 1)]
        store.togglePin(item)
    }

    private func deleteSelected() {
        let items = currentItems()
        guard !items.isEmpty else { return }
        let item = items[min(kliptState.selectedIndex, items.count - 1)]
        store.remove(item)
        // Adjust index if needed
        let newItems = currentItems()
        if kliptState.selectedIndex >= newItems.count {
            kliptState.selectedIndex = max(0, newItems.count - 1)
        }
    }

    private func setupPreviewNavigation() {
        PreviewPanel.shared.onMoveUp = { [weak self] in
            guard let self = self else { return nil }
            let items = self.currentItems()
            guard !items.isEmpty else { return nil }
            self.kliptState.selectedIndex = max(0, self.kliptState.selectedIndex - 1)
            return items[min(self.kliptState.selectedIndex, items.count - 1)]
        }
        PreviewPanel.shared.onMoveDown = { [weak self] in
            guard let self = self else { return nil }
            let items = self.currentItems()
            guard !items.isEmpty else { return nil }
            self.kliptState.selectedIndex = min(items.count - 1, self.kliptState.selectedIndex + 1)
            return items[min(self.kliptState.selectedIndex, items.count - 1)]
        }
    }

    private func cancel() {
        dismiss()
    }

    private func currentItems() -> [ClipItem] {
        switch kliptState.selectedTab {
        case .all: return store.items
        case .text: return store.textItems
        case .images: return store.imageItems
        case .files: return store.fileItems
        case .pinned: return store.pinnedItems
        case .settings: return []
        }
    }

    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, !self.ignoreClickOutside else { return }
            self.dismiss()
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    deinit {}
}

// MARK: - Drop target overlay for the panel

class KliptDropTargetView: NSView {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
        super.init(frame: .zero)
        registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            .string,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.url"),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NotificationCenter.default.post(name: .dragEnteredKlipt, object: nil)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NotificationCenter.default.post(name: .dragExitedKlipt, object: nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NotificationCenter.default.post(name: .dragExitedKlipt, object: nil)
        let pasteboard = sender.draggingPasteboard

        // Try files first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            for url in urls {
                store.add(ClipItem(fileURL: url))
            }
            NotificationCenter.default.post(name: .itemAdded, object: nil)
            return true
        }

        // Try images
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], let image = images.first {
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                store.add(ClipItem(imageData: png))
                NotificationCenter.default.post(name: .itemAdded, object: nil)
                return true
            }
        }

        // Try text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            store.add(ClipItem(text: text))
            NotificationCenter.default.post(name: .itemAdded, object: nil)
            return true
        }

        return false
    }
}
