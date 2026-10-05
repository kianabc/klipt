import Foundation
import SwiftUI

@Observable
class ClipboardStore {
    private(set) var items: [ClipItem] = []
    private let storageURL: URL

    /// `storageURL` is injectable so tests can exercise the real add/trim/expiry
    /// rules against a throwaway file rather than the user's actual clips.
    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let kliptDir = appSupport.appendingPathComponent("Klipt", isDirectory: true)
            try? FileManager.default.createDirectory(at: kliptDir, withIntermediateDirectories: true)
            // Restrict directory permissions to owner only
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: kliptDir.path)
            self.storageURL = kliptDir.appendingPathComponent("clips.json")
        }
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
        var item = item
        // Deduplicate text items, carrying the pin across.
        //
        // This used to delete the old copy and insert a fresh, unpinned one,
        // which silently unpinned anything you re-copied — and re-copying is
        // exactly what you do with text worth pinning. Once unpinned it was no
        // longer protected from trimming or expiry, so it quietly vanished
        // later. Images and files were unaffected because only text is
        // deduplicated, which is why this looked like a text-only problem.
        if item.type == .text, let text = item.textContent {
            var wasPinned = false
            items.removeAll { existing in
                guard existing.type == .text, existing.textContent == text else { return false }
                if existing.isPinned { wasPinned = true }
                return true
            }
            if wasPinned { item.isPinned = true }
        }

        items.insert(item, at: 0)
        trimExcessItems(type: item.type)
        save()

        // Every clip enters through here — pasted, dropped, screenshotted or
        // pulled from another Mac. Only locally-made ones are pushed back up:
        // a clip that arrived already carries the machine it came from, and
        // re-sending it would bounce it around forever.
        if item.sourceDevice == nil {
            Task { @MainActor in SyncEngine.shared.push(item) }
        }
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
        let days = KliptSettings.shared.expirationDays
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
