import AppKit
import ApplicationServices
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TextInjectionService {
    enum Outcome: Equatable {
        case inserted(InjectionStrategyPreference)
        case failed(String)
    }

    /// Last non-Cadence app the user was in. Updated continuously so Studio being
    /// frontmost when Fn is pressed does not steal the paste target.
    private(set) var targetApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?

    init() {
        startFrontmostTracking()
    }

    deinit {
        // Observer removal is best-effort; MainActor isolation blocks direct access in deinit.
    }

    private func startFrontmostTracking() {
        captureFrontmostIfExternal()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.noteActivated(app)
            }
        }
    }

    private func noteActivated(_ app: NSRunningApplication) {
        let id = app.bundleIdentifier ?? ""
        if Self.isCadence(id) || Self.isIgnoredSystemApp(id) { return }
        targetApp = app
        CadenceLog.debug("Inject track frontmost=\(id)")
    }

    private func captureFrontmostIfExternal() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        noteActivated(front)
    }

    /// Capture the app the user is typing in *before* HUD / polish can steal focus.
    func rememberTargetApp() {
        captureFrontmostIfExternal()
        // If the only "frontmost" was a system overlay, keep the last real target.
        if let target = targetApp, !Self.isIgnoredSystemApp(target.bundleIdentifier) {
            CadenceLog.info(
                "Inject target=\(target.bundleIdentifier ?? "?") \(target.localizedName ?? "")"
            )
        } else if let cursor = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.todesktop.230313mzl4w4u92"
        ).first {
            targetApp = cursor
            CadenceLog.info("Inject fallback target=Cursor")
        } else {
            CadenceLog.error("Inject target unknown. Click into the app you want to paste into, then hold Fn")
        }
    }

    func insert(
        _ text: String,
        context: ModelContext,
        replaceSelection: Bool = false
    ) async -> Outcome {
        guard !text.isEmpty else { return .failed("Empty text") }

        let front = resolvedTarget()
        let bundleID = front?.bundleIdentifier
        let preference = preferredStrategy(for: bundleID, context: context)
        let electron = Self.isElectronLike(bundleID)
        let axTrusted = AXIsProcessTrusted()

        let order: [InjectionStrategyPreference]
        switch preference {
        case .auto:
            if axTrusted {
                // Electron: clipboard paste is more reliable than AX value writes.
                order = electron
                    ? [.clipboard, .accessibility, .keyEvents]
                    : [.clipboard, .accessibility, .keyEvents]
            } else {
                order = [.clipboard, .keyEvents]
            }
        case .accessibility:
            order = axTrusted ? [.accessibility, .clipboard] : [.clipboard]
        case .clipboard:
            order = [.clipboard, .keyEvents]
        case .keyEvents:
            order = [.keyEvents, .clipboard]
        }

        CadenceLog.info(
            "Inject axTrusted=\(axTrusted) electron=\(electron) order=\(order.map(\.rawValue)) chars=\(text.count) app=\(bundleID ?? "?")"
        )

        if front == nil || Self.isCadence(bundleID) {
            // Keep text on clipboard so the user can ⌘V into the right app.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .failed("No target app. Click into the app you want to paste into, then hold Fn. Text is on the clipboard.")
        }

        // macOS discards synthesized key events from processes that are not trusted for
        // Accessibility, so every strategy here would no-op while reporting success.
        guard axTrusted else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            CadenceLog.error("Inject blocked: Accessibility not granted — text left on clipboard")
            return .failed(InjectionError.needsManualPaste.errorDescription ?? "Enable Accessibility")
        }

        await waitForModifiersToClear()
        await activateTarget(front)

        var lastError = "Unknown injection failure"
        for strategy in order {
            do {
                switch strategy {
                case .accessibility:
                    try insertViaAccessibility(text, replaceSelection: replaceSelection)
                    CadenceLog.info("Inject OK via accessibility")
                    return .inserted(.accessibility)
                case .clipboard:
                    try await insertViaClipboard(text, into: front, electron: electron, axTrusted: axTrusted)
                    CadenceLog.info("Inject OK via clipboard")
                    return .inserted(.clipboard)
                case .keyEvents:
                    try insertViaKeyEvents(text)
                    CadenceLog.info("Inject OK via keyEvents")
                    return .inserted(.keyEvents)
                case .auto:
                    continue
                }
            } catch {
                lastError = error.localizedDescription
                CadenceLog.error("Inject \(strategy.rawValue) failed: \(lastError)")
            }
        }
        // Always leave text on the pasteboard as a fallback.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .failed(lastError)
    }

    func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return nil }

        var selected: CFTypeRef?
        if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
           let string = selected as? String,
           !string.isEmpty
        {
            return string
        }
        return nil
    }

    private func resolvedTarget() -> NSRunningApplication? {
        if let target = targetApp,
           target.isTerminated == false,
           !Self.isCadence(target.bundleIdentifier),
           !Self.isIgnoredSystemApp(target.bundleIdentifier)
        {
            return target
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           !Self.isCadence(front.bundleIdentifier),
           !Self.isIgnoredSystemApp(front.bundleIdentifier)
        {
            return front
        }
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.todesktop.230313mzl4w4u92"
        ).first
    }

    private static func isCadence(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == Bundle.main.bundleIdentifier
            || bundleID == "com.cadence.dictation"
            || bundleID == "com.cadence.compare"
    }

    /// Notification Center, loginwindow, etc. briefly steal focus and break paste.
    private static func isIgnoredSystemApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return true }
        let ignored: Set<String> = [
            "com.apple.UserNotificationCenter",
            "com.apple.notificationcenterui",
            "com.apple.loginwindow",
            "com.apple.SecurityAgent",
            "com.apple.systempreferences",
            "com.apple.Preferences",
            "com.apple.controlcenter",
            "com.apple.TextInputUI.xpc.CursorUIViewService",
            "com.apple.Spotlight",
            "com.apple.WindowManager",
            "com.apple.dock",
            "com.apple.finder",
        ]
        if ignored.contains(id) { return true }
        if id.hasPrefix("com.apple.WebKit.") { return true }
        if id.hasPrefix("com.apple.ScreenContinuity") { return true }
        return false
    }

    private static func isElectronLike(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        let needles = [
            "todesktop", "cursor", "vscode", "code", "slack", "discord",
            "notion", "figma", "spotify", "electron", "chrome", "brave",
            "arc", "edge", "linear", "obsidian", "warp"
        ]
        return needles.contains { id.contains($0) }
    }

    private func preferredStrategy(for bundleID: String?, context: ModelContext) -> InjectionStrategyPreference {
        guard let bundleID else { return .auto }
        var descriptor = FetchDescriptor<InjectionProfile>(
            predicate: #Predicate { $0.bundleIdentifier == bundleID }
        )
        descriptor.fetchLimit = 1
        if let profile = try? context.fetch(descriptor).first {
            return profile.preferredStrategy
        }
        if Self.isElectronLike(bundleID) { return .clipboard }
        return .auto
    }

    private func insertViaAccessibility(_ text: String, replaceSelection: Bool) throws {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusStatus == .success, let focusedRef else {
            throw InjectionError.noFocusedElement
        }
        let focused = focusedRef as! AXUIElement

        if replaceSelection {
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selected) == .success,
               selected as? String != nil
            {
                let setStatus = AXUIElementSetAttributeValue(
                    focused,
                    kAXSelectedTextAttribute as CFString,
                    text as CFTypeRef
                )
                if setStatus == .success { return }
            }
        }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
           let current = valueRef as? String
        {
            var rangeRef: CFTypeRef?
            var insertion = current + text
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
               CFGetTypeID(rangeRef!) == AXValueGetTypeID()
            {
                let axRange = rangeRef as! AXValue
                var range = CFRange()
                if AXValueGetValue(axRange, .cfRange, &range) {
                    let start = min(range.location, current.utf16.count)
                    let end = min(start + max(range.length, 0), current.utf16.count)
                    let ns = current as NSString
                    insertion = ns.substring(to: start) + text + ns.substring(from: end)
                    let setValue = AXUIElementSetAttributeValue(
                        focused,
                        kAXValueAttribute as CFString,
                        insertion as CFTypeRef
                    )
                    if setValue == .success {
                        var newRange = CFRange(location: start + text.utf16.count, length: 0)
                        if let newAX = AXValueCreate(.cfRange, &newRange) {
                            AXUIElementSetAttributeValue(
                                focused,
                                kAXSelectedTextRangeAttribute as CFString,
                                newAX
                            )
                        }
                        return
                    }
                }
            }
        }

        let selectedSet = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedSet == .success { return }

        throw InjectionError.accessibilityFailed
    }

    private func insertViaClipboard(
        _ text: String,
        into app: NSRunningApplication?,
        electron: Bool,
        axTrusted: Bool
    ) async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw InjectionError.clipboardFailed
        }

        // Electron needs the target activated + a beat before ⌘V, or it swallows the event.
        await activateTarget(app)
        let settleNs: UInt64 = electron ? 180_000_000 : 60_000_000
        try await Task.sleep(nanoseconds: settleNs)

        _ = axTrusted
        try postCommandV(to: app)
    }

    private func postCommandV(to app: NSRunningApplication?) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        else {
            throw InjectionError.clipboardFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand

        // Exactly one delivery path. Posting to both the pid and the HID tap makes the
        // target receive ⌘V twice and paste the transcript twice.
        // Electron reads the window-server stream rather than per-process events, so the
        // HID tap is preferred whenever activation actually landed.
        let isFrontmost = app?.isActive == true
        if isFrontmost || app == nil {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        } else if let pid = app?.processIdentifier, pid > 0 {
            CadenceLog.debug("Inject target not frontmost — posting ⌘V to pid \(pid)")
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }

    private func waitForModifiersToClear() async {
        for _ in 0..<40 {
            let leftover = NSEvent.modifierFlags.intersection([.option, .command, .control, .shift, .function])
            if leftover.isEmpty { return }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    private func activateTarget(_ app: NSRunningApplication?) async {
        guard let app, !Self.isCadence(app.bundleIdentifier) else { return }
        if #available(macOS 14.0, *) {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    private func insertViaKeyEvents(_ text: String) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            let encoded = String(scalar).utf16.map { UniChar($0) }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw InjectionError.keyEventsFailed
            }
            encoded.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

enum InjectionError: LocalizedError {
    case noFocusedElement
    case accessibilityFailed
    case clipboardFailed
    case keyEventsFailed
    case needsManualPaste

    var errorDescription: String? {
        switch self {
        case .noFocusedElement: "No focused text element"
        case .accessibilityFailed: "Accessibility insertion failed"
        case .clipboardFailed: "Clipboard paste failed"
        case .keyEventsFailed: "Keyboard simulation failed"
        case .needsManualPaste: "Enable Accessibility for Cadence, or press ⌘V (text is on the clipboard)"
        }
    }
}
