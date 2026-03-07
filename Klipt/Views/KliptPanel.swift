import SwiftUI

enum KliptTab: String, CaseIterable {
    case all = "All"
    case text = "Text"
    case images = "Screenshots"
    case files = "Files"
    case pinned = "Pinned"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .text: return "doc.text.fill"
        case .images: return "photo.fill"
        case .files: return "doc.fill"
        case .pinned: return "pin.fill"
        case .settings: return "gearshape.fill"
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

struct KliptPanel: View {
    @Bindable var store: ClipboardStore
    let clipboardMonitor: ClipboardMonitor
    let settings: KliptSettings
    let onShortcutsChanged: () -> Void
    @State private var selectedTab: KliptTab = .all
    @State private var searchText = ""
    @State private var showClearConfirmation = false

    var itemsForCurrentTab: [ClipItem] {
        let base: [ClipItem]
        switch selectedTab {
        case .all: base = store.items
        case .text: base = store.textItems
        case .images: base = store.imageItems
        case .files: base = store.fileItems
        case .pinned: base = store.pinnedItems
        case .settings: base = []
        }

        if searchText.isEmpty { return base }
        return base.filter { item in
            switch item.type {
            case .text:
                return item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
            case .image:
                return "screenshot".localizedCaseInsensitiveContains(searchText)
            case .file:
                return item.fileName?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Tabs
            tabBar

            Divider()

            if selectedTab == .settings {
                SettingsView(settings: settings, onShortcutsChanged: onShortcutsChanged)
            } else {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search clips...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Items list
                if itemsForCurrentTab.isEmpty {
                    emptyState
                } else {
                    itemsList
                }

                Divider()

                // Footer
                footer
            }
        }
        .frame(width: 380, height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .alert("Clear all clips?", isPresented: $showClearConfirmation) {
            Button("Clear Unpinned", role: .destructive) {
                store.clearUnpinned()
            }
            Button("Clear Everything", role: .destructive) {
                store.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned items can be kept or removed too.")
        }
    }

    private var header: some View {
        HStack {
            Text("Klipt")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            Text("\(store.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(KliptTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                let count = countForTab(tab)

                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? tab.color : .secondary)

                        if tab != .settings {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(isSelected ? .primary : .tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isSelected ? tab.color.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(tab.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: selectedTab == .pinned ? "pin" : "clipboard")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text(selectedTab == .pinned ? "No pinned items" : "Nothing here yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(selectedTab == .pinned
                 ? "Pin items to keep them from expiring."
                 : "Copy text, images, or files\nand they'll appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(itemsForCurrentTab) { item in
                    ClipItemView(
                        item: item,
                        onSelect: { selectItem(item) },
                        onPin: { store.togglePin(item) },
                        onDelete: { store.remove(item) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: { showClearConfirmation = true }) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear clips")

            Spacer()

            Text("\(settings.toggleShortcutDisplayString) to toggle")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func selectItem(_ item: ClipItem) {
        clipboardMonitor.copyToClipboard(item)
        store.moveToTop(item)
        NotificationCenter.default.post(name: .hideKliptPanel, object: nil)
    }
}

extension Notification.Name {
    static let hideKliptPanel = Notification.Name("hideKliptPanel")
    static let toggleKliptPanel = Notification.Name("toggleKliptPanel")
    static let itemAdded = Notification.Name("kliptItemAdded")
}
