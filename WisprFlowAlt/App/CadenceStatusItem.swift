import AppKit
import SwiftUI

@MainActor
enum CadenceOpeners {
    static var openWindow: OpenWindowAction?
    static var openSettings: OpenSettingsAction?
}

/// AppKit status item. SwiftUI `MenuBarExtra` nested an `AXApplication` under
/// Cadence, so `kAXWindowsAttribute` returned the app instead of Studio.
@MainActor
final class CadenceStatusItem: NSObject {
    static let shared = CadenceStatusItem()

    private var statusItem: NSStatusItem?
    private var appModel: AppModel?
    private var observing = false

    func install(_ appModel: AppModel) {
        self.appModel = appModel
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Cadence")
            item.button?.image?.isTemplate = true
            statusItem = item
            CadenceLog.debug("Status item installed")
        }
        updateIcon()
        rebuildMenu()
        startObserving()
    }

    private func startObserving() {
        guard observing == false else { return }
        observing = true
        observe()
    }

    private func observe() {
        guard let appModel else { return }
        withObservationTracking {
            _ = appModel.session.state
            _ = appModel.session.lastInjectedText
            _ = appModel.settings.hasCompletedOnboarding
            _ = appModel.settings.pushToTalkShortcut.displayString
            _ = appModel.permissions.microphoneGranted
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.rebuildMenu()
                self?.observe()
            }
        }
    }

    private func updateIcon() {
        guard let appModel else { return }
        let name: String
        switch appModel.session.state {
        case .recording, .handsFree, .polishing, .finalizing, .injecting:
            name = "waveform"
        case .error:
            name = "exclamationmark.triangle"
        case .idle:
            name = "mic"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Cadence")
        statusItem?.button?.image?.isTemplate = true
    }

    private func rebuildMenu() {
        guard let appModel else { return }
        let menu = NSMenu()

        let status = NSMenuItem(title: statusText(appModel), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let hint = NSMenuItem(
            title: "Hold \(appModel.settings.pushToTalkShortcut.displayString) to dictate",
            action: nil,
            keyEquivalent: ""
        )
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Open Cadence", action: #selector(openStudioMenu(_:)), keyEquivalent: ""))
        let listening: Bool
        switch appModel.session.state {
        case .recording, .handsFree: listening = true
        default: listening = false
        }
        menu.addItem(
            NSMenuItem(
                title: listening ? "Stop Listening" : "Start Hands-Free Dictation",
                action: #selector(toggleHandsFree(_:)),
                keyEquivalent: ""
            )
        )
        let paste = NSMenuItem(
            title: "Paste Last Transcript",
            action: #selector(pasteLast(_:)),
            keyEquivalent: ""
        )
        paste.isEnabled = appModel.session.lastInjectedText.isEmpty == false
        menu.addItem(paste)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsMenu(_:)), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        if appModel.settings.hasCompletedOnboarding == false {
            menu.addItem(NSMenuItem(title: "Setup Wizard…", action: #selector(openOnboardingMenu(_:)), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let stats = NSMenuItem(
            title: "\(StatsStore.shared.todayWords) words today · Streak \(StatsStore.shared.streak)",
            action: nil,
            keyEquivalent: ""
        )
        stats.isEnabled = false
        menu.addItem(stats)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit \(CadenceBrand.name)",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem?.menu = menu
    }

    private func statusText(_ appModel: AppModel) -> String {
        switch appModel.session.state {
        case .idle: return appModel.permissions.microphoneGranted ? "Ready" : "Microphone needed"
        case .recording, .handsFree: return "Listening"
        case .finalizing: return "Finishing…"
        case .polishing: return "Cleaning up…"
        case .injecting: return "Inserting…"
        case .error(let message): return message
        }
    }

    @objc private func openStudioMenu(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let exists = NSApp.windows.contains { window in
            window.title == "Cadence" && window.frame.height >= 40
        }
        if exists {
            CadenceWindowSpace.revealStudio()
            return
        }
        CadenceOpeners.openWindow?(id: "studio")
        DispatchQueue.main.async {
            CadenceWindowSpace.revealStudio()
        }
    }

    @objc private func toggleHandsFree(_ sender: Any?) {
        guard let appModel else { return }
        Task { await appModel.session.toggleHandsFree() }
    }

    @objc private func pasteLast(_ sender: Any?) {
        guard let appModel else { return }
        let text = appModel.session.lastInjectedText
        guard text.isEmpty == false else { return }
        appModel.injection.rememberTargetApp()
        Task {
            _ = await appModel.injection.insert(text, context: appModel.modelContainer.mainContext)
        }
    }

    @objc private func openSettingsMenu(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let openSettings = CadenceOpeners.openSettings {
            openSettings()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        DispatchQueue.main.async {
            CadenceWindowSpace.pinVisibleChrome()
        }
    }

    @objc private func openOnboardingMenu(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        CadenceOpeners.openWindow?(id: "onboarding")
        DispatchQueue.main.async {
            CadenceWindowSpace.revealOnboarding()
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
