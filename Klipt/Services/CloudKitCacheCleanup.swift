import Foundation

/// Reclaims the CloudKit cache that Klipt's own bug filled.
///
/// Up to 1.9.6 the sync poll re-downloaded every synced image and file once a
/// minute, and CloudKit kept each one in `~/Library/Caches/CloudKit/<container>`.
/// One machine reached 400 GB. Fixing the poll stops it growing but gives
/// nothing back, and nobody is going to find that folder on their own.
///
/// This is a cache: the system owns it, rebuilds it on demand, and is free to
/// purge it at any time. Deleting it costs some re-fetching, nothing more.
/// Scoped strictly to Klipt's own container directory.
enum CloudKitCacheCleanup {
    /// Comfortably above anything healthy — the real cache is metadata plus a
    /// few recent assets — and far below the hundreds of gigabytes being
    /// cleaned up. Size-triggered rather than once-per-version so it still
    /// heals itself if anything ever reintroduces the problem.
    static let threshold: Int64 = 1_000_000_000

    /// Klipt's own cache directories under CloudKit's.
    ///
    /// Matched by name rather than constructed, because the directory is
    /// sometimes the full container id (`iCloud.app.klipt.Klipt`) and
    /// sometimes the bundle id (`app.klipt.Klipt`), and a hardcoded guess at
    /// the wrong one silently reclaims nothing. Still strictly scoped: only
    /// entries whose name contains our bundle id, only directly inside
    /// Caches/CloudKit, and never that folder itself.
    static var cacheDirectories: [URL] {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return [] }
        let cloudKit = caches.appendingPathComponent("CloudKit", isDirectory: true)
        let needle = Bundle.main.bundleIdentifier ?? "app.klipt.Klipt"
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cloudKit, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.lastPathComponent.contains(needle) }
    }

    /// Off the main thread: measuring and deleting a 400 GB tree is not quick,
    /// and none of it needs to block launch.
    static func reclaimIfBloated() {
        Task.detached(priority: .utility) {
            for directory in cacheDirectories {
                guard let size = sizeExceeding(threshold, at: directory) else {
                    continue  // within normal bounds, leave it alone
                }
                let gigabytes = Double(size) / 1_000_000_000
                NSLog(String(format: "Klipt cache: over %.1f GB in %@, clearing it",
                             gigabytes, directory.lastPathComponent))
                do {
                    try FileManager.default.removeItem(at: directory)
                    NSLog("Klipt cache: cleared \(directory.lastPathComponent)")
                } catch {
                    NSLog("Klipt cache: could not clear it — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Returns the total only once it is known to exceed `limit`, and stops
    /// walking at that point. Summing 400 GB of files exactly would take far
    /// longer than deciding it is too big.
    static func sizeExceeding(_ limit: Int64, at directory: URL) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return nil }

        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
            if total > limit { return total }
        }
        return nil
    }
}

/// `Klipt.app/Contents/MacOS/Klipt --cache-status`
///
/// Read-only. Reports what the cleanup would act on, so the claim that it
/// finds the right directory can be checked on a machine that actually has the
/// bloat — rather than assumed on one that does not.
enum CloudKitCacheStatus {
    static func report() {
        let directories = CloudKitCacheCleanup.cacheDirectories
        guard !directories.isEmpty else {
            print("no CloudKit cache directories match this app")
            print("  looked under ~/Library/Caches/CloudKit for names containing "
                  + (Bundle.main.bundleIdentifier ?? "app.klipt.Klipt"))
            return
        }
        for directory in directories {
            let over = CloudKitCacheCleanup.sizeExceeding(CloudKitCacheCleanup.threshold, at: directory)
            if let over {
                print(String(format: "%@ — over %.1f GB, WOULD BE CLEARED",
                             directory.lastPathComponent, Double(over) / 1_000_000_000))
            } else {
                print("\(directory.lastPathComponent) — under the 1 GB threshold, left alone")
            }
        }
    }
}
