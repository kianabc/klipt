import CloudKit
import Foundation
import AppKit

/// `Klipt.app/Contents/MacOS/Klipt --sync-test`
///
/// Round-trips one record through the real private database. Entitlements,
/// provisioning profile and container all have to line up for this to pass, and
/// every one of them fails silently at runtime rather than at build time — so
/// "it compiled" says nothing at all about whether sync works.
enum SyncTest {
    static func start() {
        Task { @MainActor in
            let container = CKContainer(identifier: SyncEngine.containerID)
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: "Clips", ownerName: CKCurrentUserDefaultName)

            print("sync test — container \(SyncEngine.containerID)")
            print("  this machine: \(SyncEngine.deviceName)")

            do {
                let status = try await container.accountStatus()
                let readable = ["couldNotDetermine", "available", "restricted",
                                "noAccount", "temporarilyUnavailable"]
                let label = status.rawValue < readable.count
                    ? readable[status.rawValue] : "\(status.rawValue)"
                print("  account: \(label)")
                guard status == .available else {
                    print("\nFAILED — sign in to iCloud, then retry")
                    exit(1)
                }

                _ = try? await database.modifyRecordZones(
                    saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
                print("  zone ready")

                let uuid = UUID()
                let recordID = CKRecord.ID(recordName: uuid.uuidString, zoneID: zoneID)
                let record = CKRecord(recordType: "Clip", recordID: recordID)
                let marker = "klipt sync test \(Int(Date().timeIntervalSince1970))"
                record.encryptedValues["text"] = marker
                record["createdAt"] = Date()
                record["pinned"] = 0
                record["device"] = SyncEngine.deviceName

                // modifyRecords reports per-record outcomes and does not throw
                // when an individual save fails — ignoring them turns a failed
                // write into a cheerful success message.
                let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                             savePolicy: .changedKeys)
                for (id, result) in saved.saveResults {
                    switch result {
                    case .success:
                        print("  wrote \(id.recordName)")
                    case .failure(let error):
                        print("\nFAILED to save: \(error.localizedDescription)")
                        if let ck = error as? CKError {
                            print("  CKError code \(ck.errorCode)")
                            if ck.code == .invalidArguments || ck.code == .unknownItem {
                                print("  the Clip record type probably does not exist in")
                                print("  Production. CloudKit only auto-creates schema in")
                                print("  Development; Production needs it deployed.")
                            }
                        }
                        exit(1)
                    }
                }

                let fetched = try await database.record(for: recordID)
                guard fetched.encryptedValues["text"] as? String == marker else {
                    print("\nFAILED — read back something other than what was written")
                    exit(1)
                }
                print("  read it back intact")

                // Leave nothing behind; this is the user's real iCloud.
                _ = try await database.modifyRecords(saving: [], deleting: [recordID])
                print("  cleaned up")

                print("\npassed — CloudKit is reachable and the container works")
                exit(0)
            } catch let error as CKError {
                print("\nFAILED — CKError \(error.errorCode): \(error.localizedDescription)")
                // The two that actually happen, and what each one means.
                if error.code == .notAuthenticated {
                    print("  not signed in to iCloud on this Mac")
                } else if error.code == .badContainer || error.code == .missingEntitlement {
                    print("  the entitlement or container id does not match the profile")
                }
                exit(1)
            } catch {
                print("\nFAILED — \(error.localizedDescription)")
                exit(1)
            }
        }
    }
}
