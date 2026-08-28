import AppKit
import SwiftUI

@MainActor
enum CadenceRuntime {
    static var appModel: AppModel?
}

/// SwiftUI `Window` scenes publish as `AXApplication` until this process owns a
/// real `NSWindow`. Studio itself is that window.
@MainActor
final class CadenceStudioWindow: NSObject, NSWindowDelegate {
    static let shared = CadenceStudioWindow()

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func present() {
        guard let appModel = CadenceRuntime.appModel else { return }
        if window == nil {
            window = makeWindow(appModel: appModel)
        }
        guard let window else { return }
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKey()
        CadenceWindowSpace.pinChromeIfNeeded(window)
        CadenceLog.debug("Studio NSWindow num=\(window.windowNumber) visible=\(window.isVisible)")
    }

    private func makeWindow(appModel: AppModel) -> NSWindow {
        let root = CadenceStudioView()
            .environment(appModel)
            .modelContainer(appModel.modelContainer)
            .background(PinWindowToActiveSpace())
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 500)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cadence"
        window.identifier = NSUserInterfaceItemIdentifier("studio")
        window.isRestorable = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        window.setContentSize(NSSize(width: 360, height: 500))
        window.center()
        return window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        CadenceWindowSpace.pinChromeIfNeeded(window)
    }
}
