import AppKit
import SwiftUI
import AVKit

class PreviewPanel: NSPanel {
    static let shared = PreviewPanel()

    override var canBecomeKey: Bool { true }

    private var keyMonitor: Any?
    var onMoveUp: (() -> ClipItem?)?
    var onMoveDown: (() -> ClipItem?)?

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovable = false
    }

    func toggle(item: ClipItem) {
        if isVisible {
            dismiss()
        } else {
            show(item: item)
        }
    }

    func show(item: ClipItem) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let view = PreviewContentView(item: item, onDismiss: { [weak self] in
            self?.dismiss()
        })
        let hosting = NSHostingView(rootView: view)

        let padding: CGFloat = 80
        let maxW = screenFrame.width - padding * 2
        let maxH = screenFrame.height - padding * 2

        let size: NSSize
        if item.type == .image, let img = item.nsImage {
            let cappedW = min(img.size.width, maxW)
            let cappedH = min(img.size.height, maxH)
            let ratio = min(cappedW / img.size.width, cappedH / img.size.height)
            let contentW = img.size.width * ratio
            let contentH = img.size.height * ratio
            size = NSSize(width: contentW + 32, height: contentH + 60)
        } else if item.type == .text {
            size = NSSize(width: min(560, maxW), height: min(420, maxH))
        } else if item.type == .file, let url = item.resolvedFileURL {
            let media = MediaType.detect(for: url)
            switch media {
            case .video:
                size = NSSize(width: min(720, maxW), height: min(480, maxH))
            case .audio:
                size = NSSize(width: min(420, maxW), height: min(260, maxH))
            case .none:
                size = NSSize(width: min(500, maxW), height: min(400, maxH))
            }
        } else {
            size = NSSize(width: min(500, maxW), height: min(400, maxH))
        }

        hosting.frame = NSRect(origin: .zero, size: size)
        self.contentView = hosting

        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.midY - size.height / 2
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startKeyMonitor()
    }

    func dismiss() {
        stopKeyMonitor()
        orderOut(nil)
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            switch Int(event.keyCode) {
            case 49, 53: // Space or Escape — close
                self.dismiss()
                return nil
            case 126: // Up
                if let item = self.onMoveUp?() {
                    self.show(item: item)
                }
                return nil
            case 125: // Down
                if let item = self.onMoveDown?() {
                    self.show(item: item)
                }
                return nil
            case 123, 124: // Left, Right — consume but do nothing
                return nil
            default:
                return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    deinit {
        stopKeyMonitor()
    }
}

private enum MediaType {
    case audio, video, none

    static func detect(for url: URL) -> MediaType {
        let ext = url.pathExtension.lowercased()
        let audioExts = Set(["mp3", "wav", "aac", "m4a", "flac", "aiff", "ogg", "wma"])
        let videoExts = Set(["mp4", "mov", "avi", "mkv", "m4v", "webm", "wmv", "flv"])
        if audioExts.contains(ext) { return .audio }
        if videoExts.contains(ext) { return .video }
        return .none
    }
}

struct MediaPlayerView: NSViewRepresentable {
    let url: URL
    let isVideo: Bool

    func makeNSView(context: Context) -> NSView {
        let player = AVPlayer(url: url)
        player.pause() // Don't autoplay

        if isVideo {
            let playerView = AVPlayerView()
            playerView.player = player
            playerView.controlsStyle = .inline
            playerView.showsFullScreenToggleButton = true
            return playerView
        } else {
            let playerView = AVPlayerView()
            playerView.player = player
            playerView.controlsStyle = .inline
            return playerView
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PreviewContentView: View {
    let item: ClipItem
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: item.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.type.color)
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(item.createdAt.relativeString)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.type {
        case .image:
            if let image = item.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        case .file:
            if let url = item.resolvedFileURL {
                let media = MediaType.detect(for: url)
                switch media {
                case .video:
                    MediaPlayerView(url: url, isVideo: true)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .audio:
                    VStack(spacing: 20) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 64, height: 64)
                        Text(item.fileName ?? "Audio")
                            .font(.system(size: 16, weight: .medium))
                        MediaPlayerView(url: url, isVideo: false)
                            .frame(height: 50)
                    }
                case .none:
                    VStack(spacing: 16) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 64, height: 64)
                        Text(item.fileName ?? "File")
                            .font(.system(size: 16, weight: .medium))
                        Text(url.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        case .text:
            ScrollView {
                Text(item.textContent ?? "")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
