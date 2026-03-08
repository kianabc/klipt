import SwiftUI
import AppKit

struct OnboardingStep {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let detail: String
    let keys: [(key: String, label: String)]
    let tryPrompt: String?
}

private let onboardingSteps: [OnboardingStep] = [
    OnboardingStep(
        icon: "clipboard.fill",
        iconColor: .purple,
        title: "Welcome to Klipt",
        subtitle: "Your clipboard, supercharged.",
        detail: "Everything you copy — text, images, screenshots, files — is saved automatically. Nothing gets lost.",
        keys: [],
        tryPrompt: nil
    ),
    OnboardingStep(
        icon: "bolt.fill",
        iconColor: .blue,
        title: "Quick Paste",
        subtitle: "Your most-used feature.",
        detail: "Press \u{2325}\u{2318}V to open Klipt. Use arrow keys to browse your clipboard history, then hit Enter to paste directly into whatever you were working on.",
        keys: [(key: "\u{2325}\u{2318}V", label: "open Klipt"), (key: "\u{2191}\u{2193}", label: "browse"), (key: "\u{23CE}", label: "paste")],
        tryPrompt: "Try it! Copy some text, then press \u{2325}\u{2318}V"
    ),
    OnboardingStep(
        icon: "rectangle.expand.vertical",
        iconColor: .indigo,
        title: "Expand for More",
        subtitle: "See everything at a glance.",
        detail: "Press Tab to expand Klipt into a full list view with search. Browse by category — All, Text, Screenshots, Files, and Pinned. Press Tab again to go back to compact mode.",
        keys: [(key: "tab", label: "expand/compact"), (key: "\u{2190}\u{2192}", label: "switch tabs")],
        tryPrompt: nil
    ),
    OnboardingStep(
        icon: "hand.draw.fill",
        iconColor: .green,
        title: "Drag & Drop",
        subtitle: "Move things freely.",
        detail: "Drag items out of Klipt into any app — Finder, Chrome, Slack, anything. You can also drag files into Klipt to stash them for later.",
        keys: [],
        tryPrompt: nil
    ),
    OnboardingStep(
        icon: "pin.fill",
        iconColor: .orange,
        title: "Pin Important Items",
        subtitle: "Keep what matters.",
        detail: "Pinned items never expire and stay at the top of your list. Unpin anytime. Click the pin icon or press P.",
        keys: [(key: "P", label: "toggle pin")],
        tryPrompt: nil
    ),
    OnboardingStep(
        icon: "eye.fill",
        iconColor: .cyan,
        title: "Preview Anything",
        subtitle: "See it full-size before pasting.",
        detail: "Press Space to preview any item — images at full resolution, text in a larger view, even audio and video files with a built-in player.",
        keys: [(key: "space", label: "preview"), (key: "\u{2191}\u{2193}", label: "navigate while previewing")],
        tryPrompt: nil
    ),
    OnboardingStep(
        icon: "camera.viewfinder",
        iconColor: .pink,
        title: "Screenshots, Captured",
        subtitle: "No more desktop clutter.",
        detail: "Every screenshot you take is automatically saved to Klipt. Find them in the Screenshots tab, ready to paste or drag anywhere.",
        keys: [],
        tryPrompt: nil
    ),
]

struct OnboardingView: View {
    @State private var currentStep = 0
    let onComplete: () -> Void

    private var step: OnboardingStep { onboardingSteps[currentStep] }
    private var isFirst: Bool { currentStep == 0 }
    private var isLast: Bool { currentStep == onboardingSteps.count - 1 }
    private var progress: CGFloat { CGFloat(currentStep + 1) / CGFloat(onboardingSteps.count) }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [step.iconColor.opacity(0.6), step.iconColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(.spring(response: 0.4), value: currentStep)
                }
            }
            .frame(height: 3)

            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(step.iconColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(step.iconColor.opacity(0.06))
                    .frame(width: 110, height: 110)
                Image(systemName: step.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(step.iconColor)
            }
            .padding(.bottom, 24)

            // Title
            Text(step.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 4)

            Text(step.subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(step.iconColor.opacity(0.8))
                .padding(.bottom, 16)

            // Detail
            Text(step.detail)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)
                .padding(.bottom, 16)

            // Keyboard shortcuts
            if !step.keys.isEmpty {
                HStack(spacing: 14) {
                    ForEach(step.keys.indices, id: \.self) { i in
                        HStack(spacing: 5) {
                            Text(step.keys[i].key)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(step.keys[i].label)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.4))
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            // Try prompt
            if let prompt = step.tryPrompt {
                Text(prompt)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(step.iconColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(step.iconColor.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
            }

            Spacer()

            // Navigation
            HStack(spacing: 12) {
                if !isFirst {
                    Button(action: { withAnimation(.spring(response: 0.3)) { currentStep -= 1 } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.primary.opacity(0.5))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Step dots
                HStack(spacing: 6) {
                    ForEach(0..<onboardingSteps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? step.iconColor : Color.primary.opacity(0.15))
                            .frame(width: i == currentStep ? 8 : 6, height: i == currentStep ? 8 : 6)
                            .animation(.spring(response: 0.3), value: currentStep)
                    }
                }

                Spacer()

                if isLast {
                    Button(action: onComplete) {
                        HStack(spacing: 4) {
                            Text("Get Started")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [step.iconColor, step.iconColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { withAnimation(.spring(response: 0.3)) { currentStep += 1 } }) {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(step.iconColor.opacity(0.8))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, y: 12)
    }
}

class OnboardingWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    init(onComplete: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let view = OnboardingView(onComplete: { [weak self] in
            onComplete()
            self?.orderOut(nil)
        })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 440)

        self.contentView = hosting
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovable = true
    }

    func showCentered() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
