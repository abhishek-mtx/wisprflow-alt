import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DictationSessionController {
    enum State: Equatable {
        case idle
        case recording
        case handsFree
        case finalizing
        case polishing
        case injecting
        case error(String)
    }

    var state: State = .idle
    var lastInjectedText: String = ""
    var lastError: String?

    private let speech: SpeechEngine
    private let pipeline: PostProcessPipeline
    private let injection: TextInjectionService
    private let hud: OverlayHUDController
    private let settings: AppSettings
    private let modelContainer: ModelContainer
    private var startedAt: Date?
    private var partialObserver: Task<Void, Never>?
    private var compareSessionActive = false

    init(
        speech: SpeechEngine,
        pipeline: PostProcessPipeline,
        injection: TextInjectionService,
        hud: OverlayHUDController,
        settings: AppSettings,
        modelContainer: ModelContainer
    ) {
        self.speech = speech
        self.pipeline = pipeline
        self.injection = injection
        self.hud = hud
        self.settings = settings
        self.modelContainer = modelContainer
        observeCompareSession()
    }

    func clearPermissionError() {
        lastError = nil
        if case .error = state {
            state = .idle
        }
        hud.hide()
    }

    func observeCompareSession() {
        compareSessionActive = false
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: CompareSync.sessionBegan, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.compareSessionActive = true
                CadenceLog.info("Compare session began — Cadence will transcribe without injecting")
            }
        }
        center.addObserver(forName: CompareSync.sessionEnded, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.compareSessionActive = false
            }
        }
    }

    func beginPushToTalk() async {
        if case .handsFree = state {
            // Ignore PTT begin while hands-free; release/toggle handles stop.
            return
        }
        if case .error = state {
            clearPermissionError()
        }
        guard state == .idle else { return }
        injection.rememberTargetApp()
        await startRecording(mode: .recording)
    }

    func endPushToTalk() async {
        guard state == .recording else { return }
        await finishAndInject()
    }

    func toggleHandsFree() async {
        switch state {
        case .idle:
            injection.rememberTargetApp()
            await startRecording(mode: .handsFree)
        case .handsFree:
            await finishAndInject()
        case .recording:
            // Convert hold session into hands-free keep-alive by ignoring end.
            state = .handsFree
            hud.update(title: "Hands-free listening", mode: .handsFree)
        default:
            break
        }
    }

    func cancel() async {
        partialObserver?.cancel()
        partialObserver = nil
        await speech.cancel()
        hud.hide()
        state = .idle
        startedAt = nil
    }

    private func startRecording(mode: State) async {
        CadenceLog.info("startRecording mode=\(mode)")
        if settings.showHUD {
            let title = mode == .handsFree ? "Listening" : "Listening"
            let hudMode: OverlayHUDController.Mode = mode == .handsFree ? .handsFree : .dictation
            hud.show(mode: hudMode, title: title)
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                let message = "Microphone permission denied"
                state = .error(message)
                lastError = message
                CadenceLog.error(message)
                hud.show(mode: .error, title: "Microphone needed", transcript: message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.hud.hide()
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
                return
            }
        } else if micStatus != .authorized {
            let message = "Allow Microphone for Cadence in System Settings → Privacy"
            state = .error(message)
            lastError = message
            CadenceLog.error("Microphone TCC=\(micStatus.rawValue) — \(message)")
            hud.show(mode: .error, title: "Microphone blocked", transcript: message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.hud.hide()
                if case .error = self.state {
                    self.state = .idle
                }
            }
            return
        }

        let context = modelContainer.mainContext
        let phrases = ((try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? [])
            .filter(\.isEnabled)
            .map(\.phrase)
        speech.setCustomDictionaryPhrases(phrases)

        let localeID = Self.normalizedSpeechLocale(settings.preferredLocaleIdentifier)
        do {
            try await speech.start(localeIdentifier: localeID)
            CadenceLog.info("Speech listening locale=\(localeID)")
        } catch {
            state = .error(error.localizedDescription)
            lastError = error.localizedDescription
            CadenceLog.error("Speech start failed: \(error.localizedDescription)")
            if settings.showHUD {
                hud.show(mode: .error, title: "Speech unavailable", transcript: error.localizedDescription)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.hud.hide()
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
            }
            return
        }

        state = mode
        startedAt = Date()

        partialObserver?.cancel()
        partialObserver = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.settings.showHUD {
                    self.hud.update(transcript: self.speech.partialTranscript)
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
                if self.state != .recording && self.state != .handsFree {
                    break
                }
            }
        }
    }

    private static func normalizedSpeechLocale(_ preferred: String) -> String {
        // Prefer BCP-47 like en-IN / en-US; strip calendar junk from Locale.current.identifier.
        let cleaned = preferred
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "@").first ?? preferred
        if cleaned.count >= 2 { return cleaned }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return "\(lang)-\(region)"
    }

    private func finishAndInject() async {
        partialObserver?.cancel()
        partialObserver = nil
        state = .finalizing
        CadenceLog.info("finishAndInject begin partial=\(speech.partialTranscript.count) final=\(speech.finalTranscript.count)")

        let raw = await speech.stopAndFinalize()
        CadenceLog.info("finishAndInject rawChars=\(raw.count)")
        if settings.showHUD {
            if raw.isEmpty {
                hud.show(mode: .error, title: "No speech captured", transcript: "")
            } else {
                hud.update(title: "Inserting…", mode: .polishing)
            }
        }
        if compareSessionActive, !raw.isEmpty {
            CompareSync.postCadenceTranscript(raw)
        }
        guard !raw.isEmpty else {
            let message = "I heard silence — try Listen again and speak clearly, then Stop."
            lastError = message
            CadenceLog.error("Empty transcript after finalize")
            if settings.showHUD {
                hud.show(mode: .error, title: "No speech captured", transcript: message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.hud.hide() }
            }
            state = .idle
            return
        }

        state = .polishing
        if settings.showHUD {
            hud.update(title: "Inserting…", mode: .polishing)
        }

        let target = injection.targetApp
        let context = modelContainer.mainContext
        let result = await pipeline.run(
            raw: raw,
            settings: settings,
            context: context,
            targetBundleID: target?.bundleIdentifier,
            targetAppName: target?.localizedName
        )

        if compareSessionActive {
            lastInjectedText = result.polished
            lastError = nil
            CompareSync.postCadenceTranscript(result.polished)
            CadenceLog.info("Compare session: skipped inject chars=\(result.polished.count)")
            let duration = Date().timeIntervalSince(startedAt ?? Date())
            let record = TranscriptRecord(
                rawText: result.raw,
                polishedText: result.polished,
                appBundleIdentifier: result.appBundleIdentifier,
                appDisplayName: result.appDisplayName,
                wordCount: TextNormalizer.wordCount(result.polished),
                durationSeconds: duration
            )
            context.insert(record)
            try? context.save()
            hud.hide()
            state = .idle
            startedAt = nil
            return
        }

        state = .injecting
        let outcome = await injection.insert(result.polished, context: context)
        switch outcome {
        case .inserted(let strategy):
            lastInjectedText = result.polished
            lastError = nil
            CadenceLog.info("Dictation complete via \(strategy.rawValue) chars=\(result.polished.count)")
            CadenceLog.debug("Dictation preview=\(result.polished.prefix(80))")
            let duration = Date().timeIntervalSince(startedAt ?? Date())
            let record = TranscriptRecord(
                rawText: result.raw,
                polishedText: result.polished,
                appBundleIdentifier: result.appBundleIdentifier,
                appDisplayName: result.appDisplayName,
                wordCount: TextNormalizer.wordCount(result.polished),
                durationSeconds: duration
            )
            context.insert(record)
            try? context.save()
            StatsStore.shared.record(words: record.wordCount, at: Date())
        case .failed(let message):
            lastError = message
            CadenceLog.error("Inject failed, copying to clipboard: \(message)")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.polished, forType: .string)
            lastInjectedText = result.polished
        }

        if settings.showHUD {
            let needsManualPaste = AXIsProcessTrusted() == false
            if needsManualPaste {
                hud.update(title: "Press ⌘V · enable Accessibility", mode: .polishing)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else if case .failed = outcome {
                hud.update(title: "Copied — press ⌘V", mode: .polishing)
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            } else {
                hud.update(title: "Inserted", mode: .polishing)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        hud.hide()
        state = .idle
        startedAt = nil
    }
}
