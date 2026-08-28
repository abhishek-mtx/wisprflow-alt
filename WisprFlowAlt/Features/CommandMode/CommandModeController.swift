import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CommandModeController {
    enum State: Equatable {
        case idle
        case listening
        case rewriting
        case injecting
        case error(String)
    }

    var state: State = .idle
    var lastResult: String = ""

    private let speech: SpeechEngine
    private let polish: FoundationModelsPolish
    private let injection: TextInjectionService
    private let hud: OverlayHUDController
    private let settings: AppSettings
    private let modelContainer: ModelContainer
    private var partialObserver: Task<Void, Never>?
    private var targetText: String = ""

    init(
        speech: SpeechEngine,
        polish: FoundationModelsPolish,
        injection: TextInjectionService,
        hud: OverlayHUDController,
        settings: AppSettings,
        modelContainer: ModelContainer
    ) {
        self.speech = speech
        self.polish = polish
        self.injection = injection
        self.hud = hud
        self.settings = settings
        self.modelContainer = modelContainer
    }

    func begin() async {
        guard state == .idle else { return }
        injection.rememberTargetApp()
        // Prefer current selection; fall back to last dictated text stored in history.
        if let selected = injection.selectedText(), !selected.isEmpty {
            targetText = selected
        } else if let last = latestTranscript() {
            targetText = last
        } else {
            state = .error("Select text or dictate first")
            if settings.showHUD {
                hud.show(mode: .error, title: "Command Mode", transcript: "Select text or dictate something first.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.hud.hide() }
            }
            state = .idle
            return
        }

        state = .listening
        if settings.showHUD {
            hud.show(mode: .command, title: "Command", transcript: "")
        }

        do {
            try await speech.start(localeIdentifier: settings.preferredLocaleIdentifier)
        } catch {
            state = .error(error.localizedDescription)
            hud.hide()
            return
        }

        partialObserver?.cancel()
        partialObserver = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.settings.showHUD {
                    self.hud.update(transcript: self.speech.partialTranscript)
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
                if self.state != .listening { break }
            }
        }
    }

    func end() async {
        guard state == .listening else { return }
        partialObserver?.cancel()
        partialObserver = nil
        state = .rewriting
        if settings.showHUD {
            hud.update(title: "Inserting…", mode: .polishing)
        }

        let instruction = await speech.stopAndFinalize()
        guard !instruction.isEmpty else {
            hud.hide()
            state = .idle
            return
        }

        let rewritten = await polish.rewrite(instruction: instruction, target: targetText)
        state = .injecting
        let context = modelContainer.mainContext
        let outcome = await injection.insert(rewritten, context: context, replaceSelection: true)
        if case .failed(let message) = outcome {
            state = .error(message)
        }
        lastResult = rewritten
        hud.hide()
        state = .idle
    }

    func cancel() async {
        partialObserver?.cancel()
        partialObserver = nil
        await speech.cancel()
        hud.hide()
        state = .idle
    }

    private func latestTranscript() -> String? {
        var descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first?.polishedText
    }
}
