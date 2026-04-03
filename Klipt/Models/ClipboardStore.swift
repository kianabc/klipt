import Foundation
import SwiftUI

@Observable
class ClipboardStore {
    private(set) var items: [ClipItem] = []
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let kliptDir = appSupport.appendingPathComponent("Klipt", isDirectory: true)
        try? FileManager.default.createDirectory(at: kliptDir, withIntermediateDirectories: true)
        // Restrict directory permissions to owner only
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: kliptDir.path)
        self.storageURL = kliptDir.appendingPathComponent("clips.json")
        load()
        purgeExpired()
    }

    var pinnedItems: [ClipItem] {
        items.filter { $0.isPinned }
    }

    var unpinnedItems: [ClipItem] {
        items.filter { !$0.isPinned }
    }

    var textItems: [ClipItem] {
        items.filter { $0.type == .text }
    }

    var imageItems: [ClipItem] {
        items.filter { $0.type == .image }
    }

    var fileItems: [ClipItem] {
        items.filter { $0.type == .file || $0.type == .group }
    }

    var lastItem: ClipItem? {
        items.first
    }

    private let maxItemsPerCategory = 100

    func add(_ item: ClipItem) {
        // Deduplicate text items
        if item.type == .text, let text = item.textContent {
            items.removeAll { $0.type == .text && $0.textContent == text }
        }

        items.insert(item, at: 0)
        trimExcessItems(type: item.type)
        save()
    }

    /// Remove oldest unpinned items when a category exceeds the limit
    private func trimExcessItems(type: ClipItemType) {
        var categoryItems = items.enumerated().filter { $0.element.type == type }
        let unpinned = categoryItems.filter { !$0.element.isPinned }
        guard unpinned.count > maxItemsPerCategory else { return }
        // Remove excess from the end (oldest)
        let toRemove = unpinned.suffix(unpinned.count - maxItemsPerCategory)
        let idsToRemove = Set(toRemove.map { $0.element.id })
        items.removeAll { idsToRemove.contains($0.id) }
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        save()
    }

    func moveToTop(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let moved = items.remove(at: index)
        items.insert(moved, at: 0)
        save()
    }

    func purgeExpired() {
        let days = LicenseManager.shared.isLicensed ? KliptSettings.shared.expirationDays : 1
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        // Ensure file is owner-readable only
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
    }
}
