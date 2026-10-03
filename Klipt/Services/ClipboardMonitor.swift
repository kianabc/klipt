import AppKit
import Foundation

class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Pasteboard markers that mean "do not record this".
    ///
    /// `ConcealedType` is what password managers set. `TransientType` marks
    /// content not meant to outlive the moment. Either one is a clear request
    /// from the writing app, and the whole convention only works if readers
    /// actually respect it.
    private static let privateTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    private static func isPrivate(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        return privateTypes.contains { types.contains($0) }
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Password managers and similar tools mark what they put on the
        // pasteboard, by convention from nspasteboard.com. Honour it: a
        // clipboard manager that quietly keeps your passwords in a plist is a
        // liability, and once clips sync between machines it would replicate
        // them too. Checked before anything is read, so the secret is never
        // even held in memory here.
        if Self.isPrivate(pasteboard) { return }

        // Check for images first (before files, since image files have both URL and image data)
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let path = ClipItem.saveImageToDisk(pngData)
            store.add(ClipItem(imageFilePath: path))
            return
        }

        // Check for files
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let url = urls.first {
            store.add(ClipItem(fileURL: url))
            return
        }

        // Check for text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            store.add(ClipItem(text: text))
            return
        }
    }

    /// Write an item back to the system clipboard so CMD+V pastes it
    func copyToClipboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = item.resolvedImageData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let url = item.resolvedFileURL {
                let accessed = url.startAccessingSecurityScopedResource()
                let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp", "heic"]
                if imageExts.contains(url.pathExtension.lowercased()),
                   let data = try? Data(contentsOf: url),
                   let image = NSImage(data: data) {
                    // Image file — paste as image data
                    pasteboard.writeObjects([image])
                } else {
                    pasteboard.writeObjects([url as NSURL])
                }
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
        case .group:
            let urls = item.resolvedGroupFileURLs
            let nsurls: [NSURL] = urls.map { url in
                _ = url.startAccessingSecurityScopedResource()
                return url as NSURL
            }
            pasteboard.writeObjects(nsurls)
            for url in urls { url.stopAccessingSecurityScopedResource() }
        }

        // Update change count so we don't re-capture our own paste
        lastChangeCount = pasteboard.changeCount
    }
}
