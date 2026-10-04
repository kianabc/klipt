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
        button.image = showingDot ? Self.badged(base) : base
    }

    /// A template image is a single-colour mask: the menu bar paints every
    /// opaque pixel the same shade. So a dot drawn straight onto the glyph is
    /// the same colour as the glyph and simply disappears. It needs a
    /// transparent gap punched around it to read as a separate mark.
    ///
    /// The glyph is also drawn slightly smaller and offset, so the badge sits
    /// in genuinely empty space rather than on top of the clipboard shape.
    static func badged(_ base: NSImage) -> NSImage {
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            let inset: CGFloat = 3
            let glyph = NSRect(x: rect.minX, y: rect.minY,
                               width: rect.width - inset, height: rect.height - inset)
            base.draw(in: glyph)

            let diameter: CGFloat = 6
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter,
                             width: diameter, height: diameter)

            // Clear a ring first; without it the dot merges into the glyph.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()

            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
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
