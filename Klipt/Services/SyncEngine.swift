import CloudKit
import Foundation

enum SyncPreference {
    private static let key = "app.klipt.syncEnabled"
    /// Off by default. Sync moves clipboard contents off the machine, which is
    /// the opposite of what the app promises everywhere else — that has to be
    /// a choice someone makes, not a default they discover.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Syncs clips between the user's own Macs through their private iCloud
/// database. See docs/SYNC.md for why this exists and what it deliberately does
/// not try to be — in short, it is for history and pinned items, not for racing
/// Universal Clipboard on latency.
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    static let containerID = "iCloud.app.klipt.Klipt"
    private static let recordType = "Clip"
    private static let zoneName = "Clips"

    /// This machine, as shown beside a clip that arrived from elsewhere.
    static let deviceName: String = Host.current().localizedName ?? "a Mac"

    private lazy var database = CKContainer(identifier: Self.containerID).privateCloudDatabase
    private let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    private weak var store: ClipboardStore?
    private var pending: [ClipItem] = []
    private var flushTimer: Timer?
    private var started = false

    private init() {}

    // MARK: Lifecycle

    func start(store: ClipboardStore) {
        self.store = store
        guard SyncPreference.enabled, !started else { return }
        started = true
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        do {
            let status = try await CKContainer(identifier: Self.containerID).accountStatus()
            guard status == .available else {
                NSLog("Klipt sync: iCloud unavailable (status \(status.rawValue))")
                return
            }
            try await ensureZone()
            await pull()
        } catch {
            NSLog("Klipt sync: could not start — \(error.localizedDescription)")
        }
    }

    /// A custom zone rather than the default one: it is what makes incremental
    /// change tokens possible later, and the default zone does not support them.
    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try? await database.modifyRecordZones(saving: [zone], deleting: [])
    }

    // MARK: Push

    /// Queue a locally-copied clip. Not sent immediately: people copy dozens of
    /// times a minute, and CloudKit throttles an app that pushes per keystroke.
    func push(_ item: ClipItem) {
        guard SyncPreference.enabled, started else { return }
        // Files stay local — replicating a 2GB video to every machine is a
        // different product. Text and links only, for now.
        guard item.type == .text, item.textContent != nil else { return }
        pending.append(item)
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }
    }

    private func flush() async {
        let batch = pending
        pending = []
        guard !batch.isEmpty else { return }
        let records = batch.map(record(from:))
        do {
            _ = try await database.modifyRecords(saving: records, deleting: [],
                                                 savePolicy: .changedKeys)
            NSLog("Klipt sync: pushed \(records.count)")
        } catch {
            NSLog("Klipt sync: push failed — \(error.localizedDescription)")
        }
    }

    private func record(from item: ClipItem) -> CKRecord {
        let id = CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: id)
        record["text"] = item.textContent
        record["createdAt"] = item.createdAt
        record["pinned"] = item.isPinned ? 1 : 0
        record["device"] = Self.deviceName
        return record
    }

    // MARK: Pull

    /// Fetch everything in the zone and merge anything we have not seen.
    ///
    /// A full query rather than a change token for now: correctness first, and
    /// the volume is small. The zone exists so tokens can be added without a
    /// migration.
    func pull() async {
        guard SyncPreference.enabled, let store else { return }
        let query = CKQuery(recordType: Self.recordType,
                            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let (results, _) = try await database.records(matching: query,
                                                          inZoneWith: zoneID,
                                                          resultsLimit: 200)
            var arrived = 0
            for (_, result) in results {
                guard let record = try? result.get(),
                      let item = Self.item(from: record) else { continue }
                // Ours already, or already merged on a previous pull.
                if store.items.contains(where: { $0.id == item.id }) { continue }
                // A clip this machine wrote is not an arrival, even the first
                // time we read it back.
                let fromElsewhere = (record["device"] as? String) != Self.deviceName
                store.add(item)
                if fromElsewhere { arrived += 1 }
            }
            if arrived > 0 {
                NSLog("Klipt sync: \(arrived) arrived")
                // One signal for the whole batch — forty clips on waking is one
                // dot, not forty.
                ArrivalIndicator.shared.noteArrival(trayIsOpen: false)
            }
        } catch {
            NSLog("Klipt sync: pull failed — \(error.localizedDescription)")
        }
    }

    private static func item(from record: CKRecord) -> ClipItem? {
        guard let text = record["text"] as? String,
              let uuid = UUID(uuidString: record.recordID.recordName) else { return nil }
        return ClipItem(syncedText: text,
                        id: uuid,
                        createdAt: record["createdAt"] as? Date ?? Date(),
                        pinned: (record["pinned"] as? Int ?? 0) == 1,
                        device: record["device"] as? String)
    }
}
