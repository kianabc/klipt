import AppKit
import Foundation

/// `Klipt.app/Contents/MacOS/Klipt --updater-selftest [path/to/Klipt.app]`
///
/// Runs the install-time verification against **real bundles** rather than
/// mocks. The thing being tested is a refusal, and a mock that refuses proves
/// nothing about whether the real check would — so every case here is an actual
/// app on disk.
enum UpdaterSelfTest {
    static func start() {
        Task { @MainActor in
            var failures = 0
            func check(_ name: String, _ expectation: String, _ body: () async -> String?) async {
                let problem = await body()
                if let problem {
                    print("  ✗ \(name): \(problem)")
                    failures += 1
                } else {
                    print("  ✓ \(name) — \(expectation)")
                }
            }

            let args = CommandLine.arguments
            let candidate = args.firstIndex(of: "--updater-selftest")
                .map { $0 + 1 }
                .flatMap { $0 < args.count && !args[$0].hasPrefix("--") ? args[$0] : nil }
                ?? "build/Release-export/Klipt.app"

            print("updater selftest")

            // 1. A perfectly valid, Apple-notarised app that simply isn't ours.
            //    This is the attack the Team ID check exists for.
            let updater = Updater(currentVersion: "0.0.1")
            await check("someone else's signed app is refused",
                        "Calculator.app rejected on Team ID") {
                let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
                guard FileManager.default.fileExists(atPath: calculator.path) else {
                    return "Calculator.app not present to test against"
                }
                do {
                    try await updater.verifyForInstall(calculator)
                    return "ACCEPTED an app signed by Apple, not us"
                } catch { return nil }
            }

            let app = URL(fileURLWithPath: candidate)
            guard FileManager.default.fileExists(atPath: app.path) else {
                print("  • no build at \(candidate) — skipping the cases that need one")
                print(failures == 0 ? "\npartial pass" : "\nFAILED")
                exit(failures == 0 ? 0 : 1)
            }

            // 2. Our own notarised build, against an older running version.
            await check("our own notarised build is accepted",
                        "\(candidate) passes every check") {
                do {
                    try await updater.verifyForInstall(app)
                    return nil
                } catch { return "REFUSED our own build: \(error.localizedDescription)" }
            }

            // 3. The same build, one byte changed. The signature must not verify.
            await check("a tampered copy is refused",
                        "one flipped byte breaks the signature") {
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("klipt-selftest-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: work) }
                try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let copy = work.appendingPathComponent("Klipt.app")
                guard shell("/usr/bin/ditto", [app.path, copy.path]) else {
                    return "could not copy the bundle"
                }
                let binary = copy.appendingPathComponent("Contents/MacOS/Klipt")
                guard let handle = try? FileHandle(forUpdating: binary) else {
                    return "could not open the binary to tamper with it"
                }
                // Append rather than overwrite: we only need the seal broken.
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data([0x00]))
                try? handle.close()
                do {
                    try await updater.verifyForInstall(copy)
                    return "ACCEPTED a modified bundle"
                } catch { return nil }
            }

            // 4. A downgrade. An old release must not be replayable to bring a
            //    fixed bug back.
            await check("a downgrade is refused",
                        "an older version cannot be replayed") {
                let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                guard let raw = plist?["CFBundleShortVersionString"] as? String,
                      let version = SemanticVersion(raw) else {
                    return "the build does not state a version"
                }
                let newer = "\(version.major + 1).0.0"
                let fromFuture = Updater(currentVersion: newer)
                do {
                    try await fromFuture.verifyForInstall(app)
                    return "ACCEPTED \(version) while running \(newer)"
                } catch { return nil }
            }

            print(failures == 0 ? "\nall passed" : "\n\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
    }

    private static func shell(_ path: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
