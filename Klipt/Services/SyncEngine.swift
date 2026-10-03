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
    private var pollTimer: Timer?

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
            startPolling()
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

    /// Poll rather than subscribe, for now.
    ///
    /// CloudKit push subscriptions would be lighter, but they need the app to
    /// handle remote notifications and they are best-effort anyway. A minute of
    /// latency is irrelevant for history and pinned items, which is all this
    /// syncs — see docs/SYNC.md on why this deliberately does not chase
    /// Universal Clipboard's speed.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pull() }
        }
    }

    // MARK: Push

    /// Queue a locally-copied clip. Not sent immediately: people copy dozens of
    /// times a minute, and CloudKit throttles an app that pushes per keystroke.
    func push(_ item: ClipItem) {
        guard SyncPreference.enabled, started else { return }
        switch item.type {
        case .text:
            guard item.textContent != nil else { return }
        case .image, .file:
            break
        default:
            // Grouped file drops are not carried yet.
            return
        }
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
        let records = batch.compactMap(record(from:))
        guard !records.isEmpty else { return }
        do {
            _ = try await database.modifyRecords(saving: records, deleting: [],
                                                 savePolicy: .changedKeys)
            NSLog("Klipt sync: pushed \(records.count)")
        } catch {
            NSLog("Klipt sync: push failed — \(error.localizedDescription)")
        }
    }

    /// Anything larger than this is left on the machine it was copied on.
    /// Assets count against the user's own iCloud storage, and a clipboard
    /// quietly uploading a disk image is not a trade anyone agreed to.
    private static let maxAssetBytes = 25 * 1024 * 1024

    private func record(from item: ClipItem) -> CKRecord? {
        let id = CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: id)
        record["createdAt"] = item.createdAt
        record["pinned"] = item.isPinned ? 1 : 0
        record["device"] = Self.deviceName

        switch item.type {
        case .text:
            record["kind"] = "text"
            // text is an Encrypted String in the schema — end-to-end
            // encrypted, so not even Apple can read a clip. Plain subscripting
            // would not write it and it would read back nil.
            record.encryptedValues["text"] = item.textContent

        case .image:
            guard let source = item.imageFileURL ?? Self.spill(item.imageData, as: "png"),
                  let staged = Self.stageForUpload(source) else { return nil }
            record["kind"] = "image"
            record["asset"] = CKAsset(fileURL: staged)

        case .file:
            // Copy out from under security scope first: the upload is async and
            // the scope would be long released by the time CloudKit reads it.
            guard let staged = item.withSecurityScopedAccess({ Self.stageForUpload($0) }) ?? nil
            else { return nil }
            guard let size = try? FileManager.default
                    .attributesOfItem(atPath: staged.path)[.size] as? Int,
                  size <= Self.maxAssetBytes else {
                NSLog("Klipt sync: skipping \(item.fileName ?? "a file") — larger than 25 MB")
                try? FileManager.default.removeItem(at: staged)
                return nil
            }
            record["kind"] = "file"
            record["asset"] = CKAsset(fileURL: staged)
            record["fileName"] = item.fileName ?? staged.lastPathComponent
            record["fileUTI"] = item.fileUTI

        default:
            return nil
        }
        return record
    }

    /// CKAsset reads its file lazily during upload, so it needs one that will
    /// still be there and still be readable.
    private static func stageForUpload(_ source: URL) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("klipt-upload-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Older image clips kept their bytes inline rather than on disk.
    private static func spill(_ data: Data?, as ext: String) -> URL? {
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("klipt-inline-\(UUID().uuidString).\(ext)")
        return (try? data.write(to: url)) == nil ? nil : url
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
        guard let uuid = UUID(uuidString: record.recordID.recordName) else { return nil }
        let createdAt = record["createdAt"] as? Date ?? Date()
        let pinned = (record["pinned"] as? Int ?? 0) == 1
        let device = record["device"] as? String
        // Records written before images and files synced carry no kind.
        let kind = record["kind"] as? String ?? "text"

        switch kind {
        case "text":
            guard let text = record.encryptedValues["text"] as? String else { return nil }
            return ClipItem(syncedText: text, id: uuid, createdAt: createdAt,
                            pinned: pinned, device: device)

        case "image":
            guard let asset = record["asset"] as? CKAsset, let source = asset.fileURL,
                  let data = try? Data(contentsOf: source) else { return nil }
            // CloudKit's own copy is temporary and is cleaned up behind us.
            let path = ClipItem.saveImageToDisk(data, timestamp: createdAt)
            return ClipItem(syncedImagePath: path, id: uuid, createdAt: createdAt,
                            pinned: pinned, device: device)

        case "file":
            guard let asset = record["asset"] as? CKAsset, let source = asset.fileURL
            else { return nil }
            let name = record["fileName"] as? String ?? source.lastPathComponent
            // Namespaced by record id so two Macs sending the same filename do
            // not overwrite each other.
            let dir = ClipItem.syncedFilesDirectory.appendingPathComponent(uuid.uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil
                else { return nil }
            }
            return ClipItem(syncedFile: destination, name: name,
                            uti: record["fileUTI"] as? String,
                            id: uuid, createdAt: createdAt, pinned: pinned, device: device)

        default:
            return nil
        }
    }
}
