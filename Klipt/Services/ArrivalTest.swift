import AppKit

/// `Klipt.app/Contents/MacOS/Klipt --arrival-test`
///
/// Puts the arrival dot up so it can actually be looked at. The real trigger is
/// a clip syncing from another machine, which is a slow and awkward way to
/// check that a menu bar badge draws correctly in both menu bar appearances.
enum ArrivalTest {
    static func start() {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)

            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                         accessibilityDescription: "Klipt")?
                .withSymbolConfiguration(config)

            let indicator = ArrivalIndicator.shared
            indicator.attach(to: item)

            // Render both states to disk: "the dot never drew" and "the dot
            // drew but is invisible in a menu bar" look identical from here.
            if let base = item.button?.image {
                let out = FileManager.default.temporaryDirectory
                for (name, image) in [("base", base), ("badged", ArrivalIndicator.badged(base))] {
                    guard let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { continue }
                    let url = out.appendingPathComponent("klipt-icon-\(name).png")
                    try? png.write(to: url)
                    print("  wrote \(url.path)  size=\(image.size)  template=\(image.isTemplate)")
                }
            } else {
                print("  NO BASE IMAGE — attach captured nothing, the dot can never draw")
            }

            print("arrival test — watch the menu bar")
            print("  reduce motion: \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")

            print("  arrival with the tray open → no dot expected")
            indicator.noteArrival(trayIsOpen: true)
            try? await Task.sleep(for: .seconds(2))

            print("  arrival with the tray closed → pulse, then a dot")
            indicator.noteArrival(trayIsOpen: false)
            try? await Task.sleep(for: .seconds(3))

            print("  a burst → still one dot, not several")
            for _ in 0..<5 { indicator.noteArrival(trayIsOpen: false) }
            try? await Task.sleep(for: .seconds(3))

            print("  local copy → dot clears")
            indicator.localActivity()
            try? await Task.sleep(for: .seconds(2))

            print("  arrival again, then opening the tray → dot clears")
            indicator.noteArrival(trayIsOpen: false)
            try? await Task.sleep(for: .seconds(2))
            indicator.trayOpened()
            try? await Task.sleep(for: .seconds(2))

            print("done")
            exit(0)
        }
    }
}
