@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechEngine {
    enum Status: Equatable {
        case idle
        case preparing
        case listening
        case finalizing
        case unavailable(String)
    }

    var status: Status = .idle
    var partialTranscript: String = ""
    var finalTranscript: String = ""

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var capture = AudioCaptureSession()
    private var customPhrases: [String] = []
    private var listenStartedAt: CFAbsoluteTime = 0
    private var didLogFirstPartial = false
    private var reservedLocale: Locale?
    private var volatileText = ""

    private var didPrepareAssets = false
    private var cachedFormat: AVAudioFormat?
    private var preparedLocaleID: String?

    func setCustomDictionaryPhrases(_ phrases: [String]) {
        customPhrases = phrases
    }

    /// Warm speech assets so the first PTT is not blocked on downloads.
    func prepare(localeIdentifier: String) async {
        do {
            let locale = try await resolveLocale(localeIdentifier)
            let transcriber = Self.makeTranscriber(locale: locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                CadenceLog.info("Speech downloading on-device assets…")
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                CadenceLog.error("Speech prepare: no compatible audio format")
                return
            }
            cachedFormat = format
            preparedLocaleID = locale.identifier
            didPrepareAssets = true
            CadenceLog.info(
                "Speech assets ready locale=\(locale.identifier) format=\(Int(format.sampleRate))Hz ch=\(format.channelCount)"
            )
        } catch {
            CadenceLog.error("Speech prepare failed: \(error.localizedDescription)")
        }
    }

    func armAudioIfNeeded() {
        // Mic starts fresh each take (Apple / Murmur pattern). Warm assets only.
    }

    func start(localeIdentifier: String) async throws {
        guard status == .idle || isUnavailable else { return }
        status = .preparing
        partialTranscript = ""
        finalTranscript = ""
        volatileText = ""

        do {
            try await startSession(localeIdentifier: localeIdentifier)
        } catch {
            await tearDownSession(releaseReservation: true)
            status = .unavailable(error.localizedDescription)
            CadenceLog.error("Speech start failed: \(error.localizedDescription)")
            throw error
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return false
    }

    private func startSession(localeIdentifier: String) async throws {
        let started = CFAbsoluteTimeGetCurrent()

        guard SpeechTranscriber.isAvailable else {
            throw SpeechEngineError.unavailable
        }

        let locale = try await resolveLocale(localeIdentifier)
        let reserved = try await AssetInventory.reserve(locale: locale)
        if reserved {
            reservedLocale = locale
        }

        let transcriber = Self.makeTranscriber(locale: locale)

        if !didPrepareAssets || preparedLocaleID != locale.identifier {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                CadenceLog.info("Speech downloading on-device assets…")
                try await request.downloadAndInstall()
            }
            didPrepareAssets = true
            preparedLocaleID = locale.identifier
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                ?? cachedFormat
        else {
            throw SpeechEngineError.noCompatibleFormat
        }
        cachedFormat = format

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.transcriber = transcriber
        self.analyzer = analyzer
        listenStartedAt = started
        didLogFirstPartial = false

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        inputContinuation = continuation

        // Apple / WWDC order: start the analyzer *before* feeding mic buffers.
        try await analyzer.start(inputSequence: stream)
        CadenceLog.info("Speech analyzer started locale=\(locale.identifier)")

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self else { return }
                        self.ingestResult(text: text, isFinal: isFinal)
                        if !text.isEmpty {
                            if self.didLogFirstPartial == false {
                                self.didLogFirstPartial = true
                                let ms = Int((CFAbsoluteTimeGetCurrent() - self.listenStartedAt) * 1000)
                                CadenceLog.info("Speech first partial +\(ms)ms chars=\(text.count)")
                            } else {
                                CadenceLog.debug(
                                    "Speech \(isFinal ? "final" : "volatile") chars=\(self.partialTranscript.count)"
                                )
                            }
                        }
                    }
                }
            } catch is CancellationError {
                // Expected on stop.
            } catch {
                await MainActor.run {
                    self?.status = .unavailable(error.localizedDescription)
                    CadenceLog.error("Speech results stream: \(error.localizedDescription)")
                }
            }
        }

        capture.onLevels = { levels in
            Task { @MainActor in
                AudioMeterStore.shared.levels = levels
            }
        }
        capture.onConvertError = { message in
            Task { @MainActor in
                CadenceLog.error("Audio convert: \(message)")
            }
        }

        // Start mic only after analyzer is consuming the stream, then attach the feeder.
        try capture.start(targetFormat: format)
        capture.attach(continuation: continuation)
        status = .listening
        CadenceLog.info(
            "Audio capture live +\(Int((CFAbsoluteTimeGetCurrent() - started) * 1000))ms locale=\(locale.identifier) format=\(Int(format.sampleRate))Hz"
        )
        _ = customPhrases
        analysisTask = nil
    }

    private func resolveLocale(_ preferred: String) async throws -> Locale {
        let requested = Locale(identifier: Self.normalizedSpeechLocale(preferred))
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return supported
        }
        if let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) {
            CadenceLog.info("Speech falling back to \(english.identifier) from \(requested.identifier)")
            return english
        }
        throw SpeechEngineError.unsupportedLocale(requested.identifier)
    }

    private static func normalizedSpeechLocale(_ preferred: String) -> String {
        let stripped = preferred
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "@").first ?? preferred
        if stripped.count >= 2 { return stripped }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return "\(lang)-\(region)"
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        // progressiveTranscription = live volatile + finalized segments (WWDC / Murmur path).
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    func stopAndFinalize() async -> String {
        status = .finalizing
        capture.stop()
        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                CadenceLog.error("Speech finalize error: \(error.localizedDescription)")
                await analyzer.cancelAndFinishNow()
            }
        }

        var previous = bestTranscript
        var stableTicks = 0
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 40_000_000)
            let now = bestTranscript
            if now == previous {
                stableTicks += 1
                if stableTicks >= 8, !now.isEmpty { break }
            } else {
                stableTicks = 0
                previous = now
            }
        }

        // Prefer finalized+volatile assembly over a lone volatile that never finalized.
        let text = assembledTranscript
        await tearDownSession(releaseReservation: true)
        status = .idle
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = Int((CFAbsoluteTimeGetCurrent() - listenStartedAt) * 1000)
        CadenceLog.info("Speech finalized chars=\(trimmed.count) +\(ms)ms")
        CadenceLog.debug("Speech preview=\(trimmed.prefix(60))")
        if trimmed.isEmpty {
            CadenceLog.error("Speech finalized empty — no partials received")
        }
        partialTranscript = trimmed
        finalTranscript = trimmed
        return trimmed
    }

    func cancel() async {
        capture.stop()
        AudioMeterStore.shared.reset()
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        await tearDownSession(releaseReservation: true)
        partialTranscript = ""
        finalTranscript = ""
        volatileText = ""
        status = .idle
    }

    private func tearDownSession(releaseReservation: Bool) async {
        resultsTask?.cancel()
        analysisTask?.cancel()
        await resultsTask?.value
        resultsTask = nil
        analysisTask = nil
        analyzer = nil
        transcriber = nil
        if releaseReservation, let locale = reservedLocale {
            reservedLocale = nil
            await AssetInventory.release(reservedLocale: locale)
        }
    }

    private var bestTranscript: String {
        assembledTranscript
    }

    private var assembledTranscript: String {
        let base = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let volatile = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return volatile }
        if volatile.isEmpty { return base }
        return base + " " + volatile
    }

    /// WWDC Notes pattern: volatile replaces in-flight guess; finals append as segments.
    private func ingestResult(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isFinal {
            if finalTranscript.isEmpty {
                finalTranscript = trimmed
            } else {
                finalTranscript += " " + trimmed
            }
            volatileText = ""
            partialTranscript = assembledTranscript
        } else {
            volatileText = trimmed
            partialTranscript = assembledTranscript
        }
    }
}

private enum SpeechEngineError: LocalizedError {
    case unavailable
    case unsupportedLocale(String)
    case noCompatibleFormat

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "SpeechTranscriber is unavailable on this Mac"
        case .unsupportedLocale(let id):
            return "Speech locale unsupported: \(id)"
        case .noCompatibleFormat:
            return "No compatible audio format for SpeechAnalyzer"
        }
    }
}

/// Fresh AVAudioEngine per take — matches Apple’s live-mic sample and avoids stale taps.
final class AudioCaptureSession: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private let converter = AnalyzerBufferConverter()
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var targetFormat: AVAudioFormat?
    private var loggedFirstBuffer = false
    private var loggedConvertError = false
    private var smoothing: [Float] = Array(repeating: 0.12, count: AudioMeter.bandCount)
    private var lastMeterEmit: CFTimeInterval = 0
    var onLevels: (@Sendable ([Float]) -> Void)?
    var onConvertError: (@Sendable (String) -> Void)?

    func start(targetFormat: AVAudioFormat) throws {
        stop()
        lock.lock()
        self.targetFormat = targetFormat
        self.continuation = nil
        lock.unlock()
        loggedFirstBuffer = false
        loggedConvertError = false
        smoothing = Array(repeating: 0.12, count: AudioMeter.bandCount)
        lastMeterEmit = 0
        converter.reset(outputFormat: targetFormat)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "Cadence.Speech",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Microphone format unavailable (sampleRate=0). Another app may own the mic."]
            )
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine

        lock.lock()
        // Attach continuation after engine is live; SpeechEngine sets it via setContinuation.
        lock.unlock()
        CadenceLog.info("Audio engine started sr=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")
    }

    func setContinuation(_ continuation: AsyncStream<AnalyzerInput>.Continuation?) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func stop() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        lock.lock()
        continuation = nil
        targetFormat = nil
        lock.unlock()
    }

    private func handleTap(buffer: AVAudioPCMBuffer) {
        if loggedFirstBuffer == false {
            loggedFirstBuffer = true
            CadenceLog.debug("Audio tap first buffer frames=\(buffer.frameLength) sr=\(buffer.format.sampleRate)")
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastMeterEmit >= 0.033 {
            lastMeterEmit = now
            let bands = AudioMeter.bands(from: buffer, smoothing: &smoothing)
            onLevels?(bands)
        }

        lock.lock()
        let format = targetFormat
        let live = continuation
        lock.unlock()
        guard let format, let live else { return }

        do {
            let converted = try converter.convert(buffer)
            guard converted.frameLength > 0 else { return }
            live.yield(AnalyzerInput(buffer: converted))
        } catch {
            if !loggedConvertError {
                loggedConvertError = true
                onConvertError?(error.localizedDescription)
            }
        }
    }
}

extension AudioCaptureSession {
    /// Wire the analyzer stream after `start` so the first buffers aren't dropped.
    func attach(continuation: AsyncStream<AnalyzerInput>.Continuation) {
        setContinuation(continuation)
    }
}

/// Converts mic buffers into SpeechAnalyzer’s required format. `primeMethod = .none` is required.
final class AnalyzerBufferConverter: @unchecked Sendable {
    private let lock = NSLock()
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    func reset(outputFormat: AVAudioFormat) {
        lock.lock()
        self.outputFormat = outputFormat
        converter = nil
        lock.unlock()
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        lock.lock()
        defer { lock.unlock() }

        guard let outputFormat else {
            throw NSError(
                domain: "Cadence.Speech",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Converter has no output format"]
            )
        }

        if inputBuffer.format == outputFormat {
            return inputBuffer
        }

        if converter == nil
            || converter?.inputFormat != inputBuffer.format
            || converter?.outputFormat != outputFormat
        {
            guard let newConverter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
                throw NSError(
                    domain: "Cadence.Speech",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create AVAudioConverter"]
                )
            }
            newConverter.primeMethod = .none
            converter = newConverter
        }

        guard let converter else { return inputBuffer }
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = max(1, AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)))
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw NSError(
                domain: "Cadence.Speech",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Unable to allocate conversion buffer"]
            )
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error || error != nil {
            throw error ?? NSError(
                domain: "Cadence.Speech",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Audio conversion failed"]
            )
        }
        return out
    }
}
