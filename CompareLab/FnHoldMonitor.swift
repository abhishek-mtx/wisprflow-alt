import AppKit
import CoreGraphics
import Foundation

/// Listen-only Fn hold detector. Does not swallow the event, so Wispr Flow
/// and Cadence can bind the same key.
final class FnHoldMonitor: @unchecked Sendable {
    var onBegan: (() -> Void)?
    var onEnded: (() -> Void)?
    private(set) var isRunning = false
    var lastError: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    func start() {
        if isRunning { return }
        _ = CGPreflightListenEventAccess()
        _ = CGRequestListenEventAccess()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnHoldMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(event: event, type: type)
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: pointer
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: pointer
        )

        guard let tap else {
            lastError = "Allow Input Monitoring for Compare, then reopen the app."
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        lastError = nil
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 63 else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let isFlags = type == .flagsChanged
        let fnDown = flags.contains(.maskSecondaryFn)
        let down = type == .keyDown || (isFlags && fnDown)
        let up = type == .keyUp || (isFlags && !fnDown)

        if down, !isDown {
            isDown = true
            DispatchQueue.main.async { self.onBegan?() }
        } else if up, isDown {
            isDown = false
            DispatchQueue.main.async { self.onEnded?() }
        }
        return Unmanaged.passUnretained(event)
    }
}
