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
    /// Directory where Klipt stores captured images on disk
    static let imagesDirectory: URL = {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Klipt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Save image data to ~/Pictures/Klipt/ and return the file path
    static func saveImageToDisk(_ data: Data, timestamp: Date = Date()) -> String {
        let fileName = "Klipt_\(Int(timestamp.timeIntervalSince1970)).png"
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)
        return url.path
    }

    let id: UUID
    let type: ClipItemType
    let createdAt: Date
    var isPinned: Bool

    var textContent: String?
    var imageData: Data?       // Legacy: inline image data (old items)
    var imageFilePath: String? // Preferred: path to image file on disk
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

    init(imageFilePath: String) {
        self.id = UUID()
        self.type = .image
        self.createdAt = Date()
        self.isPinned = false
        self.imageFilePath = imageFilePath
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
        return url
    }

    /// Access a file URL with security scope, automatically releasing when done.
    func withSecurityScopedAccess<T>(_ body: (URL) -> T) -> T? {
        guard let url = resolvedFileURL else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return body(url)
    }

    /// URL of the image file on disk (if stored as a file)
    var imageFileURL: URL? {
        guard let path = imageFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Image data — loads from file on disk, falls back to legacy inline data
    var resolvedImageData: Data? {
        if let path = imageFilePath {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return imageData
    }

    var nsImage: NSImage? {
        guard let data = resolvedImageData else { return nil }
        return NSImage(data: data)
    }
}
