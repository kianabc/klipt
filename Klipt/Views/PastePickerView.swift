import SwiftUI
import AppKit
import QuickLookThumbnailing

enum KliptTab: String, CaseIterable {
    case all = "All"
    case text = "Text"
    case images = "Screenshots"
    case files = "Files"
    case pinned = "Pinned"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .files: return "doc"
        case .pinned: return "pin"
        case .settings: return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .text: return .blue
        case .images: return .purple
        case .files: return .orange
        case .pinned: return .yellow
        case .settings: return .gray
        }
    }
}

@Observable
class KliptState {
    var selectedTab: KliptTab = .all {
        didSet {
            onTabChanged?(selectedTab)
            if selectedTab != .settings {
                UserDefaults.standard.set(selectedTab.rawValue, forKey: "klipt_lastTab")
            }
        }
    }
    var selectedIndex: Int = 0 {
        didSet {
            UserDefaults.standard.set(selectedIndex, forKey: "klipt_lastIndex")
            onSelectionChanged?()
        }
    }
    var isExpanded: Bool = false
    var isPinnedToScreen: Bool = false
    var searchText: String = ""
    var focusSearch: Bool = false
    var isDragMode: Bool = false
    var onTabChanged: ((KliptTab) -> Void)?
    var onSelectionChanged: (() -> Void)?

    /// Full reset — called when a new item is added
    func reset() {
        selectedTab = .all
        selectedIndex = 0
        isExpanded = false
        isPinnedToScreen = false
        searchText = ""
        isDragMode = false
        UserDefaults.standard.set(KliptTab.all.rawValue, forKey: "klipt_lastTab")
        UserDefaults.standard.set(0, forKey: "klipt_lastIndex")
    }

    /// Restore last state — called when reopening the panel.
    /// Defaults to the tab matching the most recent item.
    func restore(latestItemType: ClipItemType? = nil) {
        if let type = latestItemType {
            selectedTab = tabForItemType(type)
        } else {
            selectedTab = .all
        }
        selectedIndex = 0
        isExpanded = false
        isPinnedToScreen = false
        searchText = ""
        isDragMode = false
    }

    func tabForItemType(_ type: ClipItemType) -> KliptTab {
        switch type {
        case .text: return .text
        case .image: return .images
        case .file: return .files
        case .group: return .files
        }
    }
}

struct KliptMainView: View {
    let store: ClipboardStore
    let clipboardMonitor: ClipboardMonitor
    let settings: KliptSettings
    @Bindable var state: KliptState
    var onConfirm: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onToggleExpand: (() -> Void)?
    var onTogglePinToScreen: (() -> Void)?
    var onShortcutsChanged: (() -> Void)?

    @State private var showClearConfirmation = false
    @State private var isDragTargeted = false
    @FocusState private var isSearchFocused: Bool

    var items: [ClipItem] {
        let base: [ClipItem]
        switch state.selectedTab {
        case .all: base = store.items
        case .text: base = store.textItems
        case .images: base = store.imageItems
        case .files: base = store.fileItems
        case .pinned: base = store.pinnedItems
        case .settings: base = []
        }
        if state.searchText.isEmpty { return base }
        return base.filter { item in
            switch item.type {
            case .text:
                return item.textContent?.localizedCaseInsensitiveContains(state.searchText) ?? false
            case .image:
                return "screenshot".localizedCaseInsensitiveContains(state.searchText)
            case .file:
                return item.fileName?.localizedCaseInsensitiveContains(state.searchText) ?? false
            case .group:
                return item.groupFileNames?.contains { $0.localizedCaseInsensitiveContains(state.searchText) } ?? false
            }
        }
    }

    var body: some View {
        Group {
            if state.isDragMode {
                dragModeContent
            } else {
                normalContent
            }
        }
        .frame(width: 480)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isDragTargeted ? Color.green.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: isDragTargeted ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 40, y: 12)
        .onReceive(NotificationCenter.default.publisher(for: .dragEnteredKlipt)) { _ in
            withAnimation(.easeOut(duration: 0.15)) { isDragTargeted = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dragExitedKlipt)) { _ in
            withAnimation(.easeOut(duration: 0.15)) { isDragTargeted = false }
        }
        .alert("Clear all clips?", isPresented: $showClearConfirmation) {
            Button("Clear Unpinned", role: .destructive) { store.clearUnpinned() }
            Button("Clear Everything", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned items can be kept or removed too.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Tabs
            HStack(spacing: 3) {
                ForEach(KliptTab.allCases, id: \.self) { tab in
                    let isSelected = state.selectedTab == tab
                    HStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .medium))
                        if isSelected && tab != .settings {
                            Text(tab == .all ? "All" : "\(countForTab(tab))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundStyle(isSelected ? tab.color : tab.color.opacity(0.4))
                    .padding(.horizontal, isSelected ? 9 : 7)
                    .padding(.vertical, 6)
                    .background(isSelected ? tab.color.opacity(tab == .settings ? 0.15 : 0.2) : Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture {
                        state.selectedTab = tab
                        state.selectedIndex = 0
                    }
                }
            }

            Spacer(minLength: 4)

            // Search & Delete buttons
            if state.selectedTab != .settings, !items.isEmpty {
                if !state.isExpanded {
                    Button(action: {
                        onToggleExpand?()
                        state.focusSearch = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                let item = items[min(state.selectedIndex, items.count - 1)]
                Button(action: {
                    store.remove(item)
                    let newItems = self.items
                    if state.selectedIndex >= newItems.count {
                        state.selectedIndex = max(0, newItems.count - 1)
                    }
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Compact content (single item preview)

    private var compactContent: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                let item = items[min(state.selectedIndex, items.count - 1)]
                VStack(spacing: 0) {
                    itemPreview(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, item.type == .text ? 20 : 10)
                        .padding(.vertical, item.type == .text ? 14 : 8)
                        .overlay(DragSourceView(item: item, onSelect: { onConfirm?() }))
                        .overlay(alignment: .topTrailing) {
                            Button(action: { onTogglePin?() }) {
                                Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(item.isPinned ? .white : .white.opacity(0.5))
                                    .frame(width: 26, height: 26)
                                    .background(item.isPinned ? Color.orange : Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                        }
                        .contextMenu { itemContextMenu(item) }

                    // Centered counter
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.2))
                        Text("\(state.selectedIndex + 1)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(item.type.color)
                        +
                        Text(" / \(items.count)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.35))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.2))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    // MARK: - Expanded content (scrollable list)

    private var expandedContent: some View {
        Group {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.3))
                TextField("Search...", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 12)
            .onChange(of: state.focusSearch) { _, focus in
                if focus {
                    isSearchFocused = true
                    state.focusSearch = false
                }
            }
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipItemView(
                                    item: item,
                                    isKeyboardSelected: index == state.selectedIndex,
                                    onSelect: { selectAndPaste(item) },
                                    onPin: { store.togglePin(item) },
                                    onDelete: { store.remove(item) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: state.selectedIndex) { _, newIndex in
                        if newIndex >= 0 && newIndex < items.count {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(items[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            if state.selectedTab != .settings {
                // Expand/collapse button
                Button(action: { onToggleExpand?() }) {
                    HStack(spacing: 5) {
                        Image(systemName: state.isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .font(.system(size: 12, weight: .medium))
                        Text(state.isExpanded ? "Compact" : "Expand")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.primary.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Lock to screen button
                Button(action: { onTogglePinToScreen?() }) {
                    Image(systemName: state.isPinnedToScreen ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(state.isPinnedToScreen ? .yellow : .secondary)
                        .frame(width: 28, height: 28)
                        .background(state.isPinnedToScreen ? Color.yellow.opacity(0.15) : Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(state.isPinnedToScreen ? "Unlock (dismiss on click away)" : "Lock on screen")

                if state.isExpanded {
                    Button(action: { showClearConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Hints
            if state.selectedTab != .settings {
                HStack(spacing: 12) {
                    shortcutHint(key: "\u{2191}\u{2193}", label: "browse")
                    if !state.isExpanded {
                        shortcutHint(key: "\u{23CE}", label: "paste")
                    }
                    shortcutHint(key: "tab", label: state.isExpanded ? "compact" : "expand")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Normal content

    private var normalContent: some View {
        VStack(spacing: 0) {
            topBar

            if state.selectedTab == .settings {
                SettingsView(settings: settings, onShortcutsChanged: { onShortcutsChanged?() })
            } else if state.isExpanded {
                expandedContent
            } else {
                compactContent
            }

            bottomBar
        }
    }

    // MARK: - Drag mode content

    private var dragModeContent: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill((isDragTargeted ? Color.green : Color.primary).opacity(0.06))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill((isDragTargeted ? Color.green : Color.primary).opacity(0.04))
                    .frame(width: 160, height: 160)
                Image(systemName: isDragTargeted ? "plus.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(isDragTargeted ? .green : .secondary)
                    .scaleEffect(isDragTargeted ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
            }

            VStack(spacing: 6) {
                Text(isDragTargeted ? "Drop it!" : "Drop to Klipt")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isDragTargeted ? .green : .primary)
                Text(isDragTargeted ? "Release to save to your clipboard" : "Drag files, images, or text here")
                    .font(.system(size: 14))
                    .foregroundStyle(isDragTargeted ? .green.opacity(0.7) : .secondary)
            }

            Spacer()
        }
        .frame(height: 340)
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: state.selectedTab == .pinned ? "pin.slash" : "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.primary.opacity(0.15))
            Text(state.selectedTab == .pinned ? "No pinned items" : "Nothing here")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func itemPreview(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item.type {
            case .text:
                HStack(spacing: 14) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(item.type.color)
                        .frame(width: 44, height: 44)
                        .background(item.type.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(item.textContent ?? "")
                        .font(.system(size: 15))
                        .lineLimit(4)
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            case .image:
                if let image = item.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

            case .file:
                if let url = item.resolvedFileURL {
                    FileThumbnailView(url: url, maxHeight: 240)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 10) {
                    if let icon = item.withSecurityScopedAccess({ NSWorkspace.shared.icon(forFile: $0.path) }) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    Text(item.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.85))
                }

            case .group:
                GroupThumbnailGridView(urls: item.resolvedGroupFileURLs)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.teal)
                    Text(item.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }

            HStack(spacing: 6) {
                Text(item.createdAt.relativeString)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
        }
    }

    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.3))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.2))
        }
    }

    private func countForTab(_ tab: KliptTab) -> Int {
        switch tab {
        case .all: return store.items.count
        case .text: return store.textItems.count
        case .images: return store.imageItems.count
        case .files: return store.fileItems.count
        case .pinned: return store.pinnedItems.count
        case .settings: return 0
        }
    }

    @ViewBuilder
    private func itemContextMenu(_ item: ClipItem) -> some View {
        if item.type == .file, let url = item.resolvedFileURL {
            Button {
                item.withSecurityScopedAccess { url in
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        if item.type == .group {
            Button {
                let urls = item.resolvedGroupFileURLs
                let accessTokens = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                for (url, accessed) in accessTokens {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
            } label: {
                Label("Show All in Finder", systemImage: "folder")
            }
        }
        if item.type == .image {
            if let url = item.imageFileURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            if let data = item.resolvedImageData {
                Button {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "Klipt_screenshot.png"
                    panel.allowedContentTypes = [.png]
                    if panel.runModal() == .OK, let saveURL = panel.url {
                        try? data.write(to: saveURL)
                        NSWorkspace.shared.activateFileViewerSelecting([saveURL])
                    }
                } label: {
                    Label("Save Image to...", systemImage: "square.and.arrow.down")
                }
            }
        }
        Button {
            clipboardMonitor.copyToClipboard(item)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Divider()
        Button {
            onTogglePin?()
        } label: {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
        }
        Button(role: .destructive) {
            store.remove(item)
            if state.selectedIndex >= items.count {
                state.selectedIndex = max(0, items.count - 1)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func selectAndPaste(_ item: ClipItem) {
        clipboardMonitor.copyToClipboard(item)
        store.moveToTop(item)
        NotificationCenter.default.post(name: .hideKlipt, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            simulatePaste()
        }
    }
}

// MARK: - File thumbnail view

struct FileThumbnailView: View {
    let url: URL
    let maxHeight: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Fallback: large file icon
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            }
        }
        .onAppear { generateThumbnail() }
        .onChange(of: url) { _, _ in
            thumbnail = nil
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        let accessed = url.startAccessingSecurityScopedResource()
        let size = CGSize(width: 460, height: maxHeight)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateRepresentations(for: request) { rep, _, error in
            if accessed { self.url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                if let rep = rep {
                    self.thumbnail = rep.nsImage
                }
            }
        }
    }
}

struct GroupThumbnailGridView: View {
    let urls: [URL]
    @State private var icons: [NSImage] = []

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Array(icons.prefix(4).enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if urls.count > 4 {
                Text("+\(urls.count - 4)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .onAppear { loadIcons() }
    }

    private func loadIcons() {
        icons = urls.prefix(4).map { url in
            let accessed = url.startAccessingSecurityScopedResource()
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            if accessed { url.stopAccessingSecurityScopedResource() }
            return icon
        }
    }
}

extension Notification.Name {
    static let hideKlipt = Notification.Name("hideKlipt")
    static let showKlipt = Notification.Name("showKlipt")
    static let itemAdded = Notification.Name("kliptItemAdded")
    static let clearUnpinned = Notification.Name("kliptClearUnpinned")
    static let dragEnteredKlipt = Notification.Name("dragEnteredKlipt")
    static let dragExitedKlipt = Notification.Name("dragExitedKlipt")
}

func simulatePaste() {
    guard AXIsProcessTrusted() else { return }

    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)

    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand
    keyUp?.post(tap: .cghidEventTap)
}
