import Foundation

/// Inspects the CloudKit cache. Deliberately cannot clear it.
///
/// Up to 1.9.6 the sync poll re-downloaded every synced image and file once a
/// minute, and CloudKit kept each copy in `~/Library/Caches/CloudKit`. One
/// machine reached 400 GB. 1.9.7 stopped the growth; 1.9.8 tried to reclaim the
/// space too, and could not: macOS protects that directory, so an ordinary app
/// gets "you don't have permission to view it" even for its own container and
/// even when the user owns the folder. Finder can list it; we cannot.
///
/// Making it work would mean asking for Full Disk Access, which is a grossly
/// disproportionate permission to hold in order to sweep a cache. So this
/// reports what it can see and nothing more — the space is reclaimed by hand,
/// once, and the poll fix stops it coming back.
enum CloudKitCacheCleanup {
    /// Comfortably above anything healthy — the real cache is metadata plus a
    /// few recent assets — and far below the hundreds of gigabytes being
    /// cleaned up. Size-triggered rather than once-per-version so it still
    /// heals itself if anything ever reintroduces the problem.
    static let threshold: Int64 = 1_000_000_000

    /// What happened when we went looking. Distinguishing "could not read the
    /// folder" from "nothing in it matched" matters: they are different
    /// problems with different fixes, and reporting both as "no match" is what
    /// made the first attempt at this undiagnosable.
    enum Lookup {
        case found([URL])
        case unreadable(String)
        case noMatch(entries: [String])
    }

    static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CloudKit", isDirectory: true)
    }

    /// Matched by name rather than constructed: the directory is sometimes the
    /// container id and sometimes the bundle id, and a hardcoded guess at the
    /// wrong one reclaims nothing. Scoped to entries whose name contains our
    /// bundle id, directly inside Caches/CloudKit, never that folder itself.
    static func lookup() -> Lookup {
        guard let root else { return .unreadable("no caches directory") }
        let needle = Bundle.main.bundleIdentifier ?? "app.klipt.Klipt"
        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)
            let mine = entries.filter { $0.lastPathComponent.contains(needle) }
            if mine.isEmpty {
                return .noMatch(entries: entries.map(\.lastPathComponent).sorted())
            }
            return .found(mine)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// Off the main thread: measuring and deleting a 400 GB tree is not quick,
    /// and none of it needs to block launch.
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
/// Read-only. Reports exactly what the cleanup sees, including why it found
/// nothing, so this is diagnosable from the machine that has the problem.
enum CloudKitCacheStatus {
    static func report() {
        print("looking in: \(CloudKitCacheCleanup.root?.path ?? "unknown")")
        print("matching names containing: \(Bundle.main.bundleIdentifier ?? "app.klipt.Klipt")")

        switch CloudKitCacheCleanup.lookup() {
        case .unreadable(let reason):
            print("\nCOULD NOT READ the folder: \(reason)")
            print("  the cleanup cannot work until this is resolved")

        case .noMatch(let entries):
            print("\nread the folder fine — \(entries.count) containers, none matching:")
            for name in entries.prefix(40) { print("  \(name)") }
            if entries.count > 40 { print("  … and \(entries.count - 40) more") }

        case .found(let directories):
            print("\nmatched \(directories.count):")
            for directory in directories {
                let over = CloudKitCacheCleanup.sizeExceeding(
                    CloudKitCacheCleanup.threshold, at: directory)
                if let over {
                    print(String(format: "  %@ — over %.1f GB, WOULD BE CLEARED",
                                 directory.lastPathComponent, Double(over) / 1_000_000_000))
                } else {
                    print("  \(directory.lastPathComponent) — under 1 GB, left alone")
                }
            }
        }
    }
}
