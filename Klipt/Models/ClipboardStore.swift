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
        items.filter { $0.type == .file }
    }

    var lastItem: ClipItem? {
        items.first
    }

    func add(_ item: ClipItem) {
        // Deduplicate text items
        if item.type == .text, let text = item.textContent {
            items.removeAll { $0.type == .text && $0.textContent == text }
        }

        items.insert(item, at: 0)
        save()
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
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
    }
}
