import AppKit
import SwiftUI

/// SwiftUI `Window` scenes restore onto a stale Space and can come back
/// miniaturized. After a crash during restore, AppKit presents a modal
/// "Do you want to reopen its windows again?" alert. If that alert is
/// off the active Space, Cadence looks frozen: close, Settings, and the
/// alert itself receive no clicks.
///
/// Do not change `collectionBehavior`. Combining `moveToActiveSpace`
/// with SwiftUI's `fullScreenNone` trips `NSWindow _validateCollectionBehavior:`
/// and aborts.
///
/// Do not assign `sharingType`. `.readWrite` is deprecated and the setter
/// drops chrome to none. Leave SwiftUI's default `.readOnly`.
@MainActor
enum CadenceWindowSpace {
    private static var observing = false

    static func pinChromeIfNeeded(_ window: NSWindow?) {
        guard let window else { return }
        // Flow Bar is an NSPanel that ignores mouse. Leave it alone.
        if window.ignoresMouseEvents { return }
        // MenuBarExtra publishes a titled Item-0 window. Treating it as AX chrome
        // makes kAXWindowsAttribute return the application instead of Studio.
        if window.frame.height < 40 { return }
        if window.title.hasPrefix("Item-") { return }
        prepareChrome(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        // Closed SwiftUI scenes stay in NSApp.windows with isVisible false.
        // orderFrontRegardless would resurrect Settings after the user closed it.
        // Only pull chrome that is already showing, but on the wrong Space.
        if window.isVisible && window.isOnActiveSpace == false {
            window.orderFrontRegardless()
        }
    }

    static func pinVisibleChrome() {
        var seen = Set<ObjectIdentifier>()
        for window in NSApp.windows {
            let id = ObjectIdentifier(window)
            if seen.contains(id) { continue }
            seen.insert(id)
            if window.styleMask.contains(.titled) && window.frame.height >= 40 && window.title.hasPrefix("Item-") == false {
                CadenceLog.debug(
                    "Window id=\(ObjectIdentifier(window)) title=\(window.title) class=\(type(of: window)) canKey=\(window.canBecomeKey) visible=\(window.isVisible) size=\(Int(window.frame.width))x\(Int(window.frame.height)) sharing=\(window.sharingType.rawValue) onSpace=\(window.isOnActiveSpace) num=\(window.windowNumber)"
                )
            }
            pinChromeIfNeeded(window)
        }
        collapseDuplicateStudioWindows()
    }

    private static func collapseDuplicateStudioWindows() {
        let studios = NSApp.windows.filter { window in
            window.title == "Cadence"
                && window.styleMask.contains(.titled)
                && window.frame.height >= 40
                && window.isVisible
        }
        guard studios.count > 1 else { return }
        CadenceLog.debug("Closing \(studios.count - 1) extra Studio window(s)")
        for window in studios.dropFirst() {
            window.close()
        }
    }

    static func revealStudio() {
        revealWindow { window in
            window.title == "Cadence" && window.styleMask.contains(.titled)
        }
    }

    static func revealOnboarding() {
        revealWindow { window in
            window.identifier?.rawValue == "onboarding"
        }
    }

    private static func prepareChrome(_ window: NSWindow) {
        window.isRestorable = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        // SwiftUI chrome can sit on screen while the AX server still publishes
        // the process as AXApplication. Announce the window so System Events
        // can press Close and Settings on a fresh launch.
        if window.windowNumber > 0 {
            NSAccessibility.post(element: window, notification: .windowCreated)
        }
    }

    private static func revealWindow(matching: (NSWindow) -> Bool) {
        let window = NSApp.windows.first(where: matching)
        guard let window else { return }
        if window.ignoresMouseEvents { return }
        prepareChrome(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        // makeKeyAndOrderFront resets sharing. orderFrontRegardless does not.
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKey()
        prepareChrome(window)
        CadenceLog.debug("reveal title=\(window.title) appActive=\(NSApp.isActive) canKey=\(window.canBecomeKey) key=\(window.isKeyWindow) main=\(window.isMainWindow) sharing=\(window.sharingType.rawValue)")
    }

    static func startObserving() {
        guard observing == false else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: Notification.Name("NSWindowDidBecomeVisibleNotification"),
            object: nil,
            queue: .main
        ) { note in
            let window = note.object as? NSWindow
            Task { @MainActor in
                pinChromeIfNeeded(window)
            }
        }
        center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                pinVisibleChrome()
            }
        }
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            let window = note.object as? NSWindow
            Task { @MainActor in
                pinChromeIfNeeded(window)
            }
        }
    }
}

struct PinWindowToActiveSpace: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            CadenceWindowSpace.pinChromeIfNeeded(view.window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CadenceWindowSpace.pinChromeIfNeeded(view.window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            CadenceWindowSpace.pinChromeIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if window.isVisible && window.isOnActiveSpace == false {
            CadenceWindowSpace.pinChromeIfNeeded(window)
        }
    }
}
