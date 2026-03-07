import SwiftUI
import AppKit

enum PastePickerTab: String, CaseIterable {
    case all = "All"
    case text = "Text"
    case images = "Screenshots"
    case files = "Files"
    case pinned = "Pinned"

    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .text: return "doc.text.fill"
        case .images: return "photo.fill"
        case .files: return "doc.fill"
        case .pinned: return "pin.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .text: return .blue
        case .images: return .purple
        case .files: return .orange
        case .pinned: return .yellow
        }
    }
}

struct PastePickerView: View {
    let store: ClipboardStore
    let clipboardMonitor: ClipboardMonitor
    @State var selectedTab: PastePickerTab = .all
    @State var selectedIndex: Int = 0

    var items: [ClipItem] {
        switch selectedTab {
        case .all: return store.items
        case .text: return store.textItems
        case .images: return store.imageItems
        case .files: return store.fileItems
        case .pinned: return store.pinnedItems
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(PastePickerTab.allCases, id: \.self) { tab in
                    let isSelected = selectedTab == tab
                    Button(action: {
                        selectedTab = tab
                        selectedIndex = 0
                    }) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? tab.color : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? tab.color.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)

            Divider()
                .padding(.top, 4)

            // Current item preview
            if items.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("Nothing here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let item = items[min(selectedIndex, items.count - 1)]
                VStack(spacing: 6) {
                    itemPreview(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    // Navigation indicator
                    HStack(spacing: 4) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                        Text("\(selectedIndex + 1) of \(items.count)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 8)
                }
            }

            Divider()

            // Hint
            HStack(spacing: 12) {
                shortcutHint(keys: ["arrow-up", "arrow-down"], label: "navigate")
                shortcutHint(keys: ["return"], label: "paste")
                shortcutHint(keys: ["esc"], label: "cancel")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 320, height: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }

    @ViewBuilder
    private func itemPreview(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(item.type.color)
                .frame(width: 28, height: 28)
                .background(item.type.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                switch item.type {
                case .text:
                    Text(item.textContent ?? "")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3)
                        .foregroundStyle(.primary)

                case .image:
                    if let image = item.nsImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                case .file:
                    HStack(spacing: 6) {
                        if let url = item.resolvedFileURL {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                        }
                        Text(item.displayTitle)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 6) {
                    Text(item.createdAt.relativeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcutHint(keys: [String], label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                let display: String = {
                    switch key {
                    case "arrow-up": return "\u{2191}"
                    case "arrow-down": return "\u{2193}"
                    case "return": return "\u{23CE}"
                    case "esc": return "esc"
                    default: return key
                    }
                }()
                Text(display)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // Called from the hosting panel's key handler
    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = min(items.count - 1, selectedIndex + 1)
    }

    func confirmSelection() {
        guard !items.isEmpty else { return }
        let item = items[min(selectedIndex, items.count - 1)]
        clipboardMonitor.copyToClipboard(item)
        store.moveToTop(item)
        NotificationCenter.default.post(name: .hidePastePicker, object: nil)
        // Simulate CMD+V to paste into the active app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulatePaste()
        }
    }

    func cancel() {
        NotificationCenter.default.post(name: .hidePastePicker, object: nil)
    }
}

extension Notification.Name {
    static let hidePastePicker = Notification.Name("hidePastePicker")
    static let showPastePicker = Notification.Name("showPastePicker")
}

/// Simulate a CMD+V keypress to paste into the frontmost app
func simulatePaste() {
    let source = CGEventSource(stateID: .combinedSessionState)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
    keyDown?.flags = .maskCommand

    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
