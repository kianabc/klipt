import AppKit

class DragMonitor {
    private var dragMonitor: Any?
    private var dragEndMonitor: Any?
    private var showTime: Date = .distantPast
    private weak var panel: KliptPanel?

    init(panel: KliptPanel) {
        self.panel = panel
    }

    func startMonitoring() {
        var lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        var dragStartTime: Date?
        var pendingShow = false

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }

            // Don't show when dragging from Klipt itself
            if DragSourceNSView.isDraggingFromKlipt { return }

            guard !panel.isVisible else { return }

            // Only show when the drag pasteboard has new content (real drag session)
            let dragPasteboard = NSPasteboard(name: .drag)
            let currentCount = dragPasteboard.changeCount
            if currentCount != lastDragChangeCount {
                lastDragChangeCount = currentCount
                let hasContent = dragPasteboard.types?.isEmpty == false
                if hasContent {
                    // Start a delay — only show if drag continues for 300ms
                    dragStartTime = Date()
                    pendingShow = true
                }
            }

            // Show after sustained drag
            if pendingShow, let start = dragStartTime,
               Date().timeIntervalSince(start) > 0.1 {
                pendingShow = false
                self.showTime = Date()
                panel.showForDrag()
            }
        }

        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            pendingShow = false
            dragStartTime = nil
            guard let self = self, let panel = self.panel else { return }
            guard panel.openedForDrag else { return }

            // Ignore mouse-up events that happen too soon after showing
            let elapsed = Date().timeIntervalSince(self.showTime)
            guard elapsed > 1.0 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if panel.openedForDrag {
                    panel.dismiss()
                }
            }
        }
    }

    func stopMonitoring() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
    }
}
