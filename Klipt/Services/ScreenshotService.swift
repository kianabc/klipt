import AppKit
import Foundation

class ScreenshotService {
    private let store: ClipboardStore
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []
    private let watchDir: URL
    private var originalLocation: String?

    init(store: ClipboardStore) {
        self.store = store

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.watchDir = appSupport.appendingPathComponent("Klipt/Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)
    }

    // Store reference for atexit cleanup
    private static weak var activeInstance: ScreenshotService?

    func start() {
        // Save original screenshot location
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        originalLocation = (task.terminationStatus == 0 && output != nil) ? output : nil

        // Snapshot existing files so we don't import old ones
        snapshotExistingFiles()

        // Redirect screenshots to our watch directory
        setScreenshotLocation(watchDir.path)

        // Disable the floating thumbnail preview for faster capture
        runDefaults(["write", "com.apple.screencapture", "show-thumbnail", "-bool", "false"])

        // Register crash-safe cleanup
        ScreenshotService.activeInstance = self
        atexit {
            ScreenshotService.activeInstance?.stop()
        }

        // Start watching
        startWatching()
    }

    func stop() {
        fileWatcher?.cancel()
        fileWatcher = nil

        // Restore original screenshot location
        if let original = originalLocation {
            setScreenshotLocation(original)
        } else {
            // Remove the custom location to revert to default (Desktop)
            runDefaults(["delete", "com.apple.screencapture", "location"])
        }

        // Restore floating thumbnail
        runDefaults(["write", "com.apple.screencapture", "show-thumbnail", "-bool", "true"])
    }

    private func snapshotExistingFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: watchDir.path)) ?? []
        knownFiles = Set(files)
    }

    private func startWatching() {
        let fd = open(watchDir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.checkForNewScreenshots()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    private func checkForNewScreenshots() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: watchDir.path) else { return }

        for file in files {
            // Skip hidden temp files — macOS writes ".Screenshot..." first, then renames
            guard !file.hasPrefix(".") else { continue }
            guard !knownFiles.contains(file) else { continue }
            knownFiles.insert(file)

            let filePath = watchDir.appendingPathComponent(file)
            let ext = filePath.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "tiff", "bmp", "gif"].contains(ext) else { continue }

            // Small delay to ensure the file is fully written
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }

                // Move screenshot to ~/Pictures/Klipt/
                let destURL = ClipItem.imagesDirectory.appendingPathComponent(file)
                try? fm.moveItem(at: filePath, to: destURL)
                self.knownFiles.remove(file)

                let item = ClipItem(imageFilePath: destURL.path)
                self.store.add(item)
                NotificationCenter.default.post(name: .itemAdded, object: nil)
            }
        }
    }

    private func setScreenshotLocation(_ path: String) {
        runDefaults(["write", "com.apple.screencapture", "location", path])
        restartSystemUIServer()
    }

    private func runDefaults(_ args: [String]) {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    private func restartSystemUIServer() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["SystemUIServer"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }
}
