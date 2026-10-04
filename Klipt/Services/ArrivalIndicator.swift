import AppKit
import CoreGraphics

/// The menu bar signal that a clip arrived from another machine.
///
/// Sync takes a few seconds, and silence reads as failure. The fix is not to be
/// faster — it is to make the wait legible. A pulse catches the eye of someone
/// looking; a dot persists for someone who wasn't, which is the likely case
/// since they were on the *other* Mac a moment ago.
///
/// The dot means "something landed here recently", never "you have unread
/// items". Clipboard history has no backlog — you never deal with a clip — so
/// unread semantics would leave it permanently lit on whichever Mac you use
/// less, and an indicator that is always on says nothing.
@MainActor
final class ArrivalIndicator {
    static let shared = ArrivalIndicator()
    private init() {}

    /// How long the dot survives once the user is actually at this machine.
    private let presenceBudget: TimeInterval = 5 * 60
    /// Beyond this with no input, we assume nobody is looking and stop
    /// spending the budget.
    private let idleThreshold: TimeInterval = 120
    private let tick: TimeInterval = 15

    private weak var statusItem: NSStatusItem?
    private var baseImage: NSImage?
    private var showingDot = false
    private var presenceSpent: TimeInterval = 0
    private var timer: Timer?

    func attach(to item: NSStatusItem) {
        statusItem = item
        baseImage = item.button?.image
        NotificationCenter.default.addObserver(
            self, selector: #selector(resetPresenceClock),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: Events that raise the signal

    /// A clip arrived from another machine.
    func noteArrival(trayIsOpen: Bool) {
        // Already looking at the list — the row simply appears. A dot would be
        // telling someone about something they can see.
        guard !trayIsOpen else { return }
        // A burst (a laptop waking to forty clips) is one pulse and one dot,
        // not forty. A fresh arrival restarts the clock rather than stacking.
        presenceSpent = 0
        if !showingDot {
            showingDot = true
            redraw()
        }
        pulse()
        startTimer()
    }

    // MARK: Events that clear it

    /// The user opened the tray — they have seen everything.
    func trayOpened() { clear() }

    /// Any local clipboard activity means the user is engaged here, so
    /// "something arrived" is already stale news.
    func localActivity() { clear() }

    private func clear() {
        guard showingDot else { return }
        showingDot = false
        presenceSpent = 0
        stopTimer()
        redraw()
    }

    // MARK: Presence

    /// The budget counts time the user is *present*, not wall clock. A clip
    /// landing on a sleeping Mac must still be announced when they sit down —
    /// expiring at 3am would drop the signal exactly when it was needed.
    @objc private func resetPresenceClock() { presenceSpent = 0 }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.spendPresence() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func spendPresence() {
        guard showingDot else { stopTimer(); return }
        guard Self.secondsSinceInput() < idleThreshold else { return }
        presenceSpent += tick
        if presenceSpent >= presenceBudget { clear() }
    }

    /// `kCGAnyInputEventType` is `~0`, which is not one of CGEventType's
    /// declared cases — so the idiomatic `CGEventType(rawValue: ~0)!` is a
    /// force-unwrap of something that can legitimately be nil. Try it, but fall
    /// back to the soonest of the individual input types rather than trapping
    /// inside a timer.
    private static func secondsSinceInput() -> TimeInterval {
        if let anyInput = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: anyInput)
        }
        let types: [CGEventType] = [.mouseMoved, .keyDown, .flagsChanged,
                                    .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    // MARK: Drawing

    private func redraw() {
        guard let button = statusItem?.button, let base = baseImage else { return }
        button.image = showingDot ? Self.tinted(base, with: Self.arrivalTint) : base
    }

    /// Klipt's own orange, from the website palette.
    static let arrivalTint = NSColor(red: 0xF5 / 255.0, green: 0x9E / 255.0,
                                     blue: 0x0B / 255.0, alpha: 1)

    /// Recolour the whole icon rather than badge it.
    ///
    /// A 6pt dot is a weak signal, and on a template image it is worse than
    /// weak: a template is a single-colour mask, so the menu bar paints the
    /// dot the same shade as the glyph and it vanishes. Tinting means giving
    /// up template rendering — the icon no longer follows the menu bar's own
    /// light/dark colour — which is the point, since standing out is the
    /// entire job.
    static func tinted(_ base: NSImage, with colour: NSColor) -> NSImage {
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            // sourceAtop keeps the glyph's alpha and replaces its colour.
            colour.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Brief, and skipped entirely under Reduce Motion — a flashing menu bar
    /// icon is genuinely unpleasant for some people, and the dot already
    /// carries the message.
    private func pulse() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let button = statusItem?.button else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            button.animator().alphaValue = 0.25
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                button.animator().alphaValue = 1
            }
        }
    }
}
