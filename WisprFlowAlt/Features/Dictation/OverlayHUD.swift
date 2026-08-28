import AppKit
import QuartzCore

/// Compact floating “Flow Bar” — AppKit-drawn so it stays visible over Electron.
@MainActor
final class OverlayHUDController {
    enum Mode {
        case dictation
        case handsFree
        case command
        case polishing
        case error
    }

    var isVisible = false
    var title = "Listening"
    var transcript = ""
    var mode: Mode = .dictation

    private var panel: NSPanel?
    private var barView: FlowBarCanvas?
    private var meterTask: Task<Void, Never>?
    private var hideWork: DispatchWorkItem?

    private let barWidth: CGFloat = 168
    private let barHeight: CGFloat = 36

    func show(mode: Mode, title: String, transcript: String = "") {
        hideWork?.cancel()
        self.mode = mode
        self.title = title
        self.transcript = transcript
        isVisible = true
        if mode == .dictation || mode == .handsFree || mode == .command {
            AudioMeterStore.shared.primeIdle()
        }
        ensurePanel()
        applyMode()
        positionPanel()
        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.level = Self.overlayLevel
        startMeterPump()
        CadenceLog.debug(
            "Flow Bar shown mode=\(String(describing: mode)) frame=\(NSStringFromRect(panel.frame)) level=\(panel.level.rawValue) visible=\(panel.isVisible)"
        )
    }

    func update(transcript: String) {
        self.transcript = transcript
        if mode == .error || mode == .polishing {
            barView?.statusText = statusLabel
            barView?.needsDisplay = true
        }
    }

    func update(title: String, mode: Mode? = nil) {
        self.title = title
        if let mode { self.mode = mode }
        applyMode()
    }

    func hide() {
        isVisible = false
        meterTask?.cancel()
        meterTask = nil
        AudioMeterStore.shared.reset()
        panel?.orderOut(nil)
    }

    private var statusLabel: String {
        if mode == .error {
            return transcript.isEmpty ? title : transcript
        }
        return title
    }

    private func applyMode() {
        guard let barView else { return }
        switch mode {
        case .dictation, .handsFree, .command:
            barView.showsWaveform = true
            barView.statusText = ""
        case .polishing, .error:
            barView.showsWaveform = false
            barView.statusText = statusLabel
        }
        barView.needsDisplay = true
    }

    private func startMeterPump() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.mode == .dictation || self.mode == .handsFree || self.mode == .command {
                    let raw = AudioMeterStore.shared.levels
                    // Downsample 28 bands → 16 cute bars.
                    let step = max(1, raw.count / 16)
                    self.barView?.levels = (0..<16).map { i in
                        let idx = min(i * step, raw.count - 1)
                        return raw[idx]
                    }
                    self.barView?.needsDisplay = true
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let canvas = FlowBarCanvas(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        self.barView = canvas

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: barWidth, height: barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        // Must precede the level assignment: isFloatingPanel forces the window to
        // .floating (3), which sits below other apps' fullscreen windows.
        panel.isFloatingPanel = true
        panel.level = Self.overlayLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.contentView = canvas
        self.panel = panel
    }

    private static var overlayLevel: NSWindow.Level {
        // High enough to sit above Electron / Cursor chrome.
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)) + 1)
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = preferredScreen()
        let visible = screen.visibleFrame
        let size = NSSize(width: barWidth, height: barHeight)
        // Small gap above the Dock — Wispr-style bottom center.
        let origin = NSPoint(
            x: floor(visible.midX - size.width / 2),
            y: floor(visible.minY + 28)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func preferredScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let underMouse = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return underMouse
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

/// Tiny dark capsule with soft waveform bars (AppKit, not SwiftUI).
final class FlowBarCanvas: NSView {
    var levels: [Float] = Array(repeating: 0.18, count: 16)
    var showsWaveform = true
    var statusText = ""

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)

        NSColor.black.withAlphaComponent(0.82).setFill()
        capsule.fill()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()

        if showsWaveform {
            drawWaveform(in: bounds)
        } else {
            drawStatus(in: bounds)
        }
    }

    private func drawWaveform(in bounds: NSRect) {
        let count = max(levels.count, 1)
        let insetX: CGFloat = 18
        let usable = bounds.width - insetX * 2
        let spacing: CGFloat = 2.5
        let barW: CGFloat = 2.5
        let totalBarsWidth = CGFloat(count) * barW + CGFloat(count - 1) * spacing
        var x = insetX + max(0, (usable - totalBarsWidth) / 2)
        let midY = bounds.midY
        let maxH = bounds.height - 12

        for level in levels.prefix(count) {
            let t = CGFloat(max(0, min(1, level)))
            let h = 4 + t * maxH
            let bar = NSRect(x: x, y: midY - h / 2, width: barW, height: h)
            let path = NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2)
            NSColor.white.withAlphaComponent(0.92).setFill()
            path.fill()
            x += barW + spacing
        }
    }

    private func drawStatus(in bounds: NSRect) {
        let text = statusText as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: origin, withAttributes: attrs)
    }
}
