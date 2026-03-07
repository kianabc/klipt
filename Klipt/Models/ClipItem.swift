import Foundation
import AppKit
import SwiftUI

enum ClipItemType: String, Codable, CaseIterable {
    case text
    case image
    case file

    var label: String {
        switch self {
        case .text: return "Text"
        case .image: return "Screenshots"
        case .file: return "Files"
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        case .file: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .text: return .blue
        case .image: return .purple
        case .file: return .orange
        }
    }
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipItemType
    let createdAt: Date
    var isPinned: Bool

    var textContent: String?
    var imageData: Data?
    var fileBookmarkData: Data?
    var fileName: String?
    var fileUTI: String?

    init(text: String) {
        self.id = UUID()
        self.type = .text
        self.createdAt = Date()
        self.isPinned = false
        self.textContent = text
    }

    init(imageData: Data) {
        self.id = UUID()
        self.type = .image
        self.createdAt = Date()
        self.isPinned = false
        self.imageData = imageData
    }

    init(fileURL: URL) {
        self.id = UUID()
        self.type = .file
        self.createdAt = Date()
        self.isPinned = false
        self.fileName = fileURL.lastPathComponent
        self.fileUTI = fileURL.pathExtension
        self.fileBookmarkData = try? fileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    var displayTitle: String {
        switch type {
        case .text:
            let preview = textContent ?? ""
            return String(preview.prefix(80))
        case .image:
            return "Screenshot"
        case .file:
            return fileName ?? "File"
        }
    }

    var resolvedFileURL: URL? {
        guard let data = fileBookmarkData else { return nil }
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if let url = url {
            _ = url.startAccessingSecurityScopedResource()
        }
        return url
    }

    var nsImage: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }
}
