import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ClipItemView: View {
    let item: ClipItem
    var isKeyboardSelected: Bool = false
    let onSelect: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Type indicator
            Image(systemName: item.type.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.type.color)
                .frame(width: 30, height: 30)
                .background(item.type.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Content
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right side
            if isHovered {
                HStack(spacing: 4) {
                    hoverButton(icon: "eye.fill", color: .accentColor) {
                        PreviewPanel.shared.show(item: item)
                    }
                    hoverButton(icon: item.isPinned ? "pin.slash.fill" : "pin.fill", color: .orange) {
                        onPin()
                    }
                    hoverButton(icon: "trash.fill", color: .red) {
                        onDelete()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.createdAt.relativeString)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.quaternary)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : isKeyboardSelected ? Color.accentColor.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isKeyboardSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .overlay(DragSourceView(item: item, onSelect: onSelect))
    }

    private func hoverButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 26, height: 26)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text:
            Text(item.displayTitle)
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary.opacity(0.85))

        case .image:
            if let image = item.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Image")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

        case .file:
            HStack(spacing: 8) {
                if let url = item.resolvedFileURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text(item.displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.85))
            }
        }
    }
}

// MARK: - AppKit drag source that handles both click-to-select and drag-out

struct DragSourceView: NSViewRepresentable {
    let item: ClipItem
    let onSelect: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.item = item
        view.onSelect = onSelect
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.item = item
        nsView.onSelect = onSelect
    }
}

class DragSourceNSView: NSView, NSDraggingSource {
    static var isDraggingFromKlipt = false

    var item: ClipItem?
    var onSelect: (() -> Void)?
    private var localMouseMonitor: Any?
    private var mouseDownPoint: NSPoint?
    private var didDrag = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitor()
        if window != nil {
            startMonitor()
        }
    }

    private func startMonitor() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self, let window = self.window, event.window == window else { return event }

            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            guard self.bounds.contains(locationInView) else {
                return event
            }

            switch event.type {
            case .leftMouseDown:
                self.mouseDownPoint = locationInWindow
                self.didDrag = false
                return nil

            case .leftMouseDragged:
                guard let origin = self.mouseDownPoint, let item = self.item else { return event }
                let dx = abs(locationInWindow.x - origin.x)
                let dy = abs(locationInWindow.y - origin.y)
                guard dx > 4 || dy > 4 else { return nil }

                self.didDrag = true
                self.startDrag(item: item, event: event)
                self.mouseDownPoint = nil
                return nil

            case .leftMouseUp:
                if !self.didDrag && self.mouseDownPoint != nil {
                    self.onSelect?()
                }
                self.mouseDownPoint = nil
                self.didDrag = false
                return nil

            default:
                return event
            }
        }
    }

    private func stopMonitor() {
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragSourceNSView.isDraggingFromKlipt = false
        if operation != [] {
            // Successful drop — close Klipty if it's open
            NotificationCenter.default.post(name: .hideKlipt, object: nil)
        }
    }

    private func startDrag(item: ClipItem, event: NSEvent) {
        DragSourceNSView.isDraggingFromKlipt = true

        switch item.type {
        case .text:
            let pasteboardItem = NSPasteboardItem()
            if let text = item.textContent {
                pasteboardItem.setString(text, forType: .string)
            }
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            draggingItem.setDraggingFrame(bounds, contents: snapshot())
            beginDraggingSession(with: [draggingItem], event: event, source: self)

        case .image:
            if let data = item.imageData {
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "Klipt_\(Int(Date().timeIntervalSince1970)).png"
                let tempURL = tempDir.appendingPathComponent(fileName)
                try? data.write(to: tempURL)

                let draggingItem = NSDraggingItem(pasteboardWriter: tempURL as NSURL)
                draggingItem.setDraggingFrame(bounds, contents: item.nsImage ?? snapshot())
                beginDraggingSession(with: [draggingItem], event: event, source: self)
            }

        case .file:
            if let url = item.resolvedFileURL {
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                draggingItem.setDraggingFrame(bounds, contents: snapshot())
                beginDraggingSession(with: [draggingItem], event: event, source: self)
            }
        }
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
        }
        image.unlockFocus()
        return image
    }

    deinit {
        stopMonitor()
    }
}

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
