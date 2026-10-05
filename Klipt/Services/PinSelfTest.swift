import Foundation
import AppKit

/// `Klipt.app/Contents/MacOS/Klipt --pin-selftest`
///
/// Exercises the rules that are supposed to keep a pinned clip alive, against
/// a throwaway store rather than the real one. Losing a pin is silent — it
/// looks like nothing happened until the clip quietly disappears days later —
/// so it needs checking outright rather than noticing in use.
enum PinSelfTest {
    static func start() {
        Task { @MainActor in
            var failures = 0
            func check(_ name: String, _ body: () -> String?) {
                if let problem = body() {
                    print("  ✗ \(name): \(problem)")
                    failures += 1
                } else {
                    print("  ✓ \(name)")
                }
            }

            func freshStore() -> ClipboardStore {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("klipt-pintest-\(UUID().uuidString).json")
                return ClipboardStore(storageURL: url)
            }

            print("pin selftest")

            // The bug: re-copying pinned text dropped the pin, after which
            // nothing protected it from trimming or expiry.
            check("re-copying pinned text keeps it pinned") {
                let store = freshStore()
                let original = ClipItem(text: "hello@klipt.app")
                store.add(original)
                guard let first = store.items.first else { return "nothing was added" }
                store.togglePin(first)
                guard store.pinnedItems.count == 1 else { return "pinning did not take" }

                store.add(ClipItem(text: "hello@klipt.app"))
                guard store.pinnedItems.count == 1 else {
                    return "pin lost — \(store.pinnedItems.count) pinned after re-copying"
                }
                guard store.textItems.count == 1 else {
                    return "left \(store.textItems.count) copies instead of deduplicating"
                }
                return nil
            }

            // Overflowing the per-category cap must evict unpinned clips only.
            check("a pinned clip survives 150 newer ones") {
                let store = freshStore()
                store.add(ClipItem(text: "keep me"))
                guard let first = store.items.first else { return "nothing was added" }
                store.togglePin(first)
                for i in 0..<150 { store.add(ClipItem(text: "filler \(i)")) }
                guard store.items.contains(where: { $0.textContent == "keep me" }) else {
                    return "the pinned clip was trimmed away"
                }
                return nil
            }

            // Expiry is the other eviction path.
            check("expiry leaves pinned clips alone") {
                let store = freshStore()
                store.add(ClipItem(text: "old but pinned"))
                guard let first = store.items.first else { return "nothing was added" }
                store.togglePin(first)
                store.purgeExpired()
                guard store.items.contains(where: { $0.textContent == "old but pinned" }) else {
                    return "expiry removed a pinned clip"
                }
                return nil
            }

            print(failures == 0 ? "\nall passed" : "\n\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
    }
}
