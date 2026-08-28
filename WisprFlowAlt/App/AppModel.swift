import AppKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    let modelContainer: ModelContainer
    let permissions: PermissionService
    let hotkeys: GlobalHotkeyService
    let speech: SpeechEngine
    let injection: TextInjectionService
    let polish: FoundationModelsPolish
    let pipeline: PostProcessPipeline
    let session: DictationSessionController
    let commandMode: CommandModeController
    let hud: OverlayHUDController
    let settings: AppSettings

    private var didBootstrap = false

    init() {
        let schema = Schema([
            DictionaryEntry.self,
            StyleProfile.self,
            AppStyleMapping.self,
            SnippetEntry.self,
            TransformRule.self,
            TranscriptRecord.self,
            InjectionProfile.self
        ])
        let configuration = ModelConfiguration(
            "WisprFlowAlt",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        settings = AppSettings()
        permissions = PermissionService()
        hotkeys = GlobalHotkeyService()
        speech = SpeechEngine()
        injection = TextInjectionService()
        polish = FoundationModelsPolish()
        pipeline = PostProcessPipeline(polish: polish)
        hud = OverlayHUDController()
        session = DictationSessionController(
            speech: speech,
            pipeline: pipeline,
            injection: injection,
            hud: hud,
            settings: settings,
            modelContainer: modelContainer
        )
        commandMode = CommandModeController(
            speech: speech,
            polish: polish,
            injection: injection,
            hud: hud,
            settings: settings,
            modelContainer: modelContainer
        )

        bootstrapIfNeeded()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true

        SeedData.ensureDefaults(in: modelContainer.mainContext)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        permissions.observeAppActivation()
        permissions.refresh()
        wireHotkeys()
        CadenceWindowSpace.startObserving()
        // Persist the migrated default so UI and tap stay in sync.
        settings.pushToTalkShortcut = settings.pushToTalkShortcut
        applyHotkeySettings()
        hotkeys.start()
        let localeID = settings.preferredLocaleIdentifier
        Task { await speech.prepare(localeIdentifier: localeID) }
        CadenceLog.debug("Bootstrap complete hotkeysRunning=\(hotkeys.isRunning) mic=\(permissions.microphoneGranted) ax=\(permissions.accessibilityTrusted) input=\(permissions.inputMonitoringTrusted)")
        // Onboarding is opened from MenuBarView once the app UI exists.
    }

    func openOnboarding() {
        guard let app = NSApp else { return }
        app.activate(ignoringOtherApps: true)
        CadenceWindowSpace.revealOnboarding()
        if NSApp.windows.contains(where: { $0.identifier?.rawValue == "onboarding" }) {
            return
        }
        NotificationCenter.default.post(name: .openOnboarding, object: nil)
        DispatchQueue.main.async {
            CadenceWindowSpace.revealOnboarding()
        }
    }

    private func wireHotkeys() {
        hotkeys.configure(
            pushToTalk: settings.pushToTalkShortcut,
            commandMode: settings.commandModeShortcut,
            cancel: KeyShortcut(keyCode: 53, modifiers: []) // Escape
        )

        let center = NotificationCenter.default
        center.addObserver(forName: .cadencePushToTalkBegan, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.session.beginPushToTalk() }
        }
        center.addObserver(forName: .cadencePushToTalkEnded, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.session.endPushToTalk() }
        }
        center.addObserver(forName: .cadenceHandsFreeToggle, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.session.toggleHandsFree() }
        }
        center.addObserver(forName: .cadenceCommandModeBegan, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.commandMode.begin() }
        }
        center.addObserver(forName: .cadenceCommandModeEnded, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.commandMode.end() }
        }
        center.addObserver(forName: .cadenceCancel, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.session.cancel()
                await self?.commandMode.cancel()
            }
        }
    }

    func applyHotkeySettings() {
        hotkeys.configure(
            pushToTalk: settings.pushToTalkShortcut,
            commandMode: settings.commandModeShortcut,
            cancel: KeyShortcut(keyCode: 53, modifiers: [])
        )
    }
}

extension Notification.Name {
    static let openOnboarding = Notification.Name("WisprFlowAlt.openOnboarding")
}
