import AppKit
import Foundation
import Observation

extension Notification.Name {
    static let cadencePushToTalkBegan = Notification.Name("cadence.pushToTalkBegan")
    static let cadencePushToTalkEnded = Notification.Name("cadence.pushToTalkEnded")
    static let cadenceHandsFreeToggle = Notification.Name("cadence.handsFreeToggle")
    static let cadenceCommandModeBegan = Notification.Name("cadence.commandModeBegan")
    static let cadenceCommandModeEnded = Notification.Name("cadence.commandModeEnded")
    static let cadenceCancel = Notification.Name("cadence.cancel")
}

/// Global hotkey monitor via CGEvent tap (listen-only — does not steal keys).
@Observable
final class GlobalHotkeyService: @unchecked Sendable {
    var isRunning = false
    var lastValidationError: String?

    private var pushToTalk = KeyShortcut.defaultPushToTalk
    private var commandMode = KeyShortcut.defaultCommandMode
    private var cancel = KeyShortcut(keyCode: 53, modifiers: [])
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var globalMonitor: Any?
    private var stopRequested = false
    /// stop() + start() in quick succession must not leave the previous tap thread alive.
    private var tapGeneration = 0
    /// Tap thread and the NSEvent monitor on main both drive the same state machine.
    private let stateLock = NSLock()
    private var isPTTDown = false
    private var isCommandDown = false
    private var lastPTTUp: Date?
    private var pttDownAt: Date?
    private var lastPTTHoldDuration: TimeInterval = 0
    private var handsFreeEnabled = true
    private var doubleTapThreshold: TimeInterval = 0.35

    func configure(pushToTalk: KeyShortcut, commandMode: KeyShortcut, cancel: KeyShortcut) {
        if let error = pushToTalk.conflictsWithSystem() {
            lastValidationError = "Push-to-talk: \(error)"
        } else if let error = commandMode.conflictsWithSystem() {
            lastValidationError = "Command Mode: \(error)"
        } else if pushToTalk == commandMode {
            lastValidationError = "Push-to-talk and Command Mode cannot share the same shortcut."
        } else {
            lastValidationError = nil
        }
        self.pushToTalk = pushToTalk
        self.commandMode = commandMode
        self.cancel = cancel

        let settings = AppSettings()
        handsFreeEnabled = settings.doubleTapHandsFreeEnabled
        doubleTapThreshold = Double(settings.doubleTapThresholdMs) / 1000.0
        CadenceLog.info("Hotkeys configured PTT=\(pushToTalk.displayString) CMD=\(commandMode.displayString)")
    }

    func start() {
        if isRunning {
            CadenceLog.info("Hotkey tap already running")
            return
        }

        // Always request; preflight can lag right after the user toggles TCC.
        let preflight = CGPreflightListenEventAccess()
        let requested = CGRequestListenEventAccess()
        CadenceLog.info("Input Monitoring preflight=\(preflight) request=\(requested)")
        if !preflight && !requested {
            CadenceLog.error("Input Monitoring denied — Fn will not register until it is granted")
        }

        stopRequested = false
        tapGeneration &+= 1
        let generation = tapGeneration
        let thread = Thread { [weak self] in self?.runTapLoop(generation: generation) }
        thread.name = "com.cadence.hotkey-tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()

        installGlobalMonitorFallback()
        isRunning = true
        lastValidationError = nil
    }

    /// The tap runs on its own run loop. On the main run loop it competes with SwiftUI,
    /// speech and polish work, and macOS disables any tap whose callback is slow to return —
    /// every such window silently drops Fn presses.
    private func runTapLoop(generation: Int) {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
            return service.handle(event: event, type: type)
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        // Listen-only only. A default tap at headInsert can swallow input and freeze the UI.
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: pointer
        )

        guard let tap else {
            let message = "Failed to create event tap. Enable Input Monitoring for Cadence, then quit and reopen the app."
            CadenceLog.error(message)
            DispatchQueue.main.async {
                self.lastValidationError = message
                self.isRunning = false
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let loop = CFRunLoopGetCurrent()
        eventTap = tap
        runLoopSource = source
        tapRunLoop = loop
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Belt and braces: if the tap is ever disabled while no event is flowing, the
        // disable callback never fires, so poll it back to life.
        let watchdog = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, 0, 2.0, 0, 0) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                CadenceLog.debug("Watchdog re-enabled event tap")
            }
        }
        CFRunLoopAddTimer(loop, watchdog, .commonModes)

        CadenceLog.info("Hotkey event tap started on dedicated thread")

        while !stopRequested && tapGeneration == generation {
            CFRunLoopRunInMode(.defaultMode, 0.25, false)
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveTimer(loop, watchdog, .commonModes)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        if tapGeneration == generation {
            eventTap = nil
            runLoopSource = nil
            tapRunLoop = nil
        }
        CadenceLog.info("Hotkey event tap stopped")
    }

    /// Secondary source so a dead tap does not mean a dead hotkey.
    /// `isPTTDown` de-duplicates when both paths deliver the same press.
    private func installGlobalMonitorFallback() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            guard let self else { return }
            let type: CGEventType
            switch event.type {
            case .keyDown: type = .keyDown
            case .keyUp: type = .keyUp
            default: type = .flagsChanged
            }
            self.process(
                keyCode: Int64(event.keyCode),
                flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                type: type
            )
        }
    }

    func stop() {
        stopRequested = true
        if let loop = tapRunLoop { CFRunLoopWakeUp(loop) }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        tapThread = nil
        isRunning = false
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                CadenceLog.debug("Re-enabled event tap after disable")
            }
            return Unmanaged.passUnretained(event)
        }

        process(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            type: type
        )
        return Unmanaged.passUnretained(event)
    }

    private func process(keyCode: Int64, flags: CGEventFlags, type: CGEventType) {
        stateLock.lock()
        defer { stateLock.unlock() }

        if type == .keyDown, cancel.matches(keyCode: keyCode, flags: flags) {
            CadenceLog.info("Cancel hotkey")
            post(.cadenceCancel)
            return
        }

        let isFlags = type == .flagsChanged
        let modifierDown = isModifierKeyDown(keyCode: keyCode, flags: flags)
        let isDown = type == .keyDown || (isFlags && modifierDown)
        let isUp = type == .keyUp || (isFlags && !modifierDown && wasOurModifier(keyCode: keyCode))

        let pttMatch: Bool = {
            if isFlags && isPTTModifier(keyCode: keyCode) && pushToTalk.matchesKeyCode(keyCode)
                && pushToTalk.modifiers.isEmpty
            {
                return true
            }
            let matchFlags = isFlags
                ? adjustedFlags(for: keyCode, flags: flags, down: isDown)
                : flags
            return pushToTalk.matches(keyCode: keyCode, flags: matchFlags)
        }()

        if pttMatch {
            if isDown && !isPTTDown {
                isPTTDown = true
                pttDownAt = Date()
                if handsFreeEnabled,
                   let last = lastPTTUp,
                   Date().timeIntervalSince(last) <= doubleTapThreshold,
                   lastPTTHoldDuration >= 0.25
                {
                    lastPTTUp = nil
                    CadenceLog.info("Hands-free toggle")
                    post(.cadenceHandsFreeToggle)
                    return
                }
                CadenceLog.info("PTT began key=\(keyCode)")
                post(.cadencePushToTalkBegan)
                return
            }
            if isUp && isPTTDown {
                isPTTDown = false
                lastPTTHoldDuration = pttDownAt.map { Date().timeIntervalSince($0) } ?? 0
                lastPTTUp = Date()
                CadenceLog.info("PTT ended holdMs=\(Int(lastPTTHoldDuration * 1000))")
                post(.cadencePushToTalkEnded)
                return
            }
        }

        if commandMode.matches(keyCode: keyCode, flags: flags) {
            if type == .keyDown && !isCommandDown {
                isCommandDown = true
                CadenceLog.info("Command mode began")
                post(.cadenceCommandModeBegan)
                return
            }
            if type == .keyUp && isCommandDown {
                isCommandDown = false
                CadenceLog.info("Command mode ended")
                post(.cadenceCommandModeEnded)
            }
        }
    }

    private func post(_ name: Notification.Name) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    private func isPTTModifier(keyCode: Int64) -> Bool {
        [55, 56, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    private func wasOurModifier(keyCode: Int64) -> Bool {
        pushToTalk.modifiers.isEmpty && pushToTalk.matchesKeyCode(keyCode)
    }

    private func isModifierKeyDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 59, 62: return flags.contains(.maskControl)
        case 58, 61: return flags.contains(.maskAlternate)
        case 56, 60: return flags.contains(.maskShift)
        case 55, 54: return flags.contains(.maskCommand)
        case 63: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    private func adjustedFlags(for keyCode: Int64, flags: CGEventFlags, down: Bool) -> CGEventFlags {
        var adjusted = flags
        if !down {
            switch keyCode {
            case 59, 62: adjusted.remove(.maskControl)
            case 58, 61: adjusted.remove(.maskAlternate)
            case 56, 60: adjusted.remove(.maskShift)
            case 55, 54: adjusted.remove(.maskCommand)
            case 63: adjusted.remove(.maskSecondaryFn)
            default: break
            }
        }
        return adjusted
    }
}
