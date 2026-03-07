import AppKit
import SwiftUI
import UniformTypeIdentifiers

class DragTrayWindow: NSPanel {
    private let store: ClipboardStore
    private var dragMonitor: Any?

    init(store: ClipboardStore) {
        self.store = store
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        let trayView = NSHostingView(rootView: DragTrayView(store: store))
        trayView.frame = NSRect(x: 0, y: 0, width: 56, height: 56)
        self.contentView = trayView
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
    }

    func startMonitoring() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return }

            if event.type == .leftMouseUp {
                self.hideTray()
                return
            }

            // Check if there's an active drag session by checking pasteboard
            let dragPasteboard = NSPasteboard(name: .drag)
            let hasContent = dragPasteboard.types?.isEmpty == false

            if hasContent && !self.isVisible {
                self.showTray(near: NSEvent.mouseLocation)
            } else if hasContent && self.isVisible {
                self.updatePosition(near: NSEvent.mouseLocation)
            }
        }
    }

    func stopMonitoring() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
    }

    private func showTray(near point: NSPoint) {
        let offset: CGFloat = 60
        setFrameOrigin(NSPoint(x: point.x + offset, y: point.y - 28))
        orderFront(nil)
    }

    private func updatePosition(near point: NSPoint) {
        let offset: CGFloat = 60
        setFrameOrigin(NSPoint(x: point.x + offset, y: point.y - 28))
    }

    private func hideTray() {
        orderOut(nil)
    }
}

struct DragTrayView: View {
    let store: ClipboardStore
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.white.opacity(0.2),
                    lineWidth: isTargeted ? 2 : 1
                )

            VStack(spacing: 2) {
                Image(systemName: isTargeted ? "plus.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isTargeted ? .green : .secondary)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)

                Text("Klipt")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString) else { return }
                    DispatchQueue.main.async {
                        store.add(ClipItem(fileURL: url))
                        NotificationCenter.default.post(name: .itemAdded, object: nil)
                    }
                }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data else { return }
                    DispatchQueue.main.async {
                        store.add(ClipItem(imageData: data))
                        NotificationCenter.default.post(name: .itemAdded, object: nil)
                    }
                }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data = data as? Data,
                          let text = String(data: data, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        store.add(ClipItem(text: text))
                        NotificationCenter.default.post(name: .itemAdded, object: nil)
                    }
                }
                return
            }
        }
    }
}
