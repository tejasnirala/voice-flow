import AppKit
import SwiftUI
import VoiceFlowCore

/// The floating pill shown while dictating. A non-activating panel: it never takes focus from the app you're
/// dictating into. Drag it anywhere; the position is saved to settings.json and reused every time it appears.
/// Created on first use and only ordered in while a dictation is in progress (no cost when idle).
@MainActor
final class IndicatorController {
    private let state: AppState
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var previous: PipelineState = .idle

    static let size = NSSize(width: 236, height: 56)

    init(state: AppState) {
        self.state = state
    }

    func pipelineChanged(to next: PipelineState) {
        defer { previous = next }
        guard state.settings.showIndicator else { hide(); return }
        hideWork?.cancel()
        switch next {
        case .recording, .transcribing, .processing, .inserting:
            show()
        case .idle:
            // Brief confirmation after a paste; otherwise (cancel, empty) hide right away.
            if previous == .inserting { hide(after: 0.8) } else { hide() }
        case .error:
            show()
            hide(after: 3)
        }
    }

    func settingsChanged() {
        if !state.settings.showIndicator { hide() }
        if let panel, state.settings.indicatorPosition == nil { panel.setFrameOrigin(Self.defaultOrigin()) }
    }

    // MARK: Panel

    private func show() {
        let panel = self.panel ?? makePanel()
        if !panel.isVisible {
            panel.setFrameOrigin(Self.origin(for: state.settings.indicatorPosition))
            panel.orderFrontRegardless()
        }
    }

    private func hide(after seconds: Double = 0) {
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork = work
        if seconds == 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let view = PillView(state: state, interaction: PillInteraction(), onDragEnded: { [weak self, weak panel] in
            guard let self, let panel else { return }
            let origin = panel.frame.origin
            self.state.update { $0.indicatorPosition = .init(x: origin.x.rounded(), y: origin.y.rounded()) }
        }, panel: { [weak panel] in panel })
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        return panel
    }

    /// Bottom center of the screen with the mouse (like Wispr Flow's pill).
    static func defaultOrigin() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return .zero }
        return NSPoint(x: (frame.midX - size.width / 2).rounded(), y: frame.minY + 20)
    }

    /// The saved position if the pill would still be on a connected screen; otherwise the default.
    static func origin(for saved: VoiceFlowCore.Settings.IndicatorPosition?) -> NSPoint {
        guard let saved else { return defaultOrigin() }
        let center = NSPoint(x: saved.x + size.width / 2, y: saved.y + size.height / 2)
        return NSScreen.screens.contains { $0.frame.contains(center) } ? NSPoint(x: saved.x, y: saved.y) : defaultOrigin()
    }
}

/// Dark capsule: live level bars while recording, a spinner while transcribing or rewriting, a check after pasting.
/// View-local state (SwiftUI's `@State` is a macro whose plugin ships only with Xcode).
@MainActor
@Observable
final class PillInteraction {
    var hovering = false
    @ObservationIgnored var dragStart: (mouse: NSPoint, origin: NSPoint)?
}

struct PillView: View {
    let state: AppState
    let interaction: PillInteraction
    let onDragEnded: () -> Void
    let panel: () -> NSWindow?

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule().fill(Color.black.opacity(0.86)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .foregroundStyle(.white)
        .frame(width: IndicatorController.size.width, height: IndicatorController.size.height)
        .contentShape(Capsule())
        .onHover { interaction.hovering = $0 }
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                guard let window = panel() else { return }
                let mouse = NSEvent.mouseLocation
                let start = interaction.dragStart ?? (mouse, window.frame.origin)
                interaction.dragStart = start
                window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
            }
            .onEnded { _ in
                interaction.dragStart = nil
                onDragEnded()
            })
        .help("Drag to move")
    }

    @ViewBuilder private var content: some View {
        switch state.pipelineState {
        case .recording where !state.audioFlowing:
            Image(systemName: "mic.fill").foregroundStyle(.white.opacity(0.6))
            Text("Starting…").font(.system(size: 12, weight: .medium)).opacity(0.8)
            Spacer(minLength: 0)
            cancelButton
        case .recording:
            Circle().fill(Color.red).frame(width: 8, height: 8)
            LevelBars(levels: state.levels)
            Spacer(minLength: 0)
            if state.handsFree || interaction.hovering { finishButton }
            cancelButton
        case .transcribing:
            ProgressView().controlSize(.small).tint(.white)
            Text("Transcribing").font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
        case .processing:
            ProgressView().controlSize(.small).tint(.white)
            Text("Rewriting").font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
        case .inserting, .idle:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Pasted").font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
        case .error(let failure):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(failure.message).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private var cancelButton: some View {
        Button { state.onCancelDictation?() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help("Cancel (Esc)")
    }

    private var finishButton: some View {
        Button { state.onFinishDictation?() } label: {
            Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help("Finish and transcribe")
    }
}

private struct LevelBars: View {
    let levels: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: 4 + 18 * levels[index])
            }
        }
        .frame(height: 22)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
