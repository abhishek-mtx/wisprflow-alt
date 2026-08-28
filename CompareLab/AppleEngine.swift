import AVFoundation
import Foundation
import Speech

enum AppleEngine {
    static func transcribe(fileURL: URL) async -> EngineResult {
        var result = EngineResult.blank(
            name: "Cadence",
            subtitle: "macOS 26 Speech Transcriber"
        )
        result.status = .running
        let locale = Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            result.status = .failed
            result.error = error.localizedDescription
            return result
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            result.status = .failed
            result.error = "Could not read recording"
            return result
        }

        let started = CFAbsoluteTimeGetCurrent()
        let probe = try? AVAudioFile(forReading: fileURL)
        let preferred = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            ?? probe?.processingFormat
            ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let box = GrowingText()
        let resultsTask = Task {
            do {
                for try await item in transcriber.results {
                    let text = String(item.text.characters)
                    box.update(text, isFinal: item.isFinal, started: started)
                }
            } catch {
                box.error = error.localizedDescription
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.prepareToAnalyze(in: preferred)
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
            let feedTask = Task.detached {
                do {
                    try Self.feed(fileURL: fileURL, format: preferred, into: continuation)
                } catch {
                    // Stream still needs to finish so the analyzer can complete.
                }
                continuation.finish()
            }
            try await analyzer.start(inputSequence: stream)
            await feedTask.value
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            result.status = .failed
            result.error = error.localizedDescription
            resultsTask.cancel()
            return result
        }

        await waitUntilStable(box)
        resultsTask.cancel()
        withExtendedLifetime(analyzer) {}

        let text = box.best.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            result.status = .failed
            result.error = box.error ?? "No speech captured"
            return result
        }
        result.status = .done
        result.transcript = text
        result.inferMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        result.firstPartialMs = box.firstPartialMs
        return result
    }

    /// Stream the WAV as AnalyzerInput in Apple’s preferred Float32 format —
    /// same path as live dictation, not DictationTranscriber file analysis.
    private static func feed(
        fileURL: URL,
        format: AVAudioFormat,
        into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let file = try AVAudioFile(forReading: fileURL)
        let converter = FileBufferConverter()
        let chunk: AVAudioFrameCount = 4096
        while true {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: chunk
            ) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            let converted = try converter.convert(buffer, to: format)
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    private static func waitUntilStable(_ box: GrowingText) async {
        var previous = box.best
        var stableTicks = 0
        let deadline = Date().addingTimeInterval(1.6)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 40_000_000)
            let now = box.best
            if now == previous {
                stableTicks += 1
                if stableTicks >= 8, !now.isEmpty { break }
            } else {
                stableTicks = 0
                previous = now
            }
        }
    }
}

/// SpeechTranscriber emits a growing hypothesis. Keep the longest / latest, do not stitch pause-finals.
private final class GrowingText: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ""
    private var final = ""
    var firstPartialMs: Int?
    var error: String?

    func update(_ text: String, isFinal: Bool, started: CFAbsoluteTime) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if firstPartialMs == nil {
            firstPartialMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        last = TranscriptStitcher.absorbRevision(existing: last, incoming: trimmed)
        if isFinal {
            final = TranscriptStitcher.absorbRevision(existing: final, incoming: trimmed)
        }
    }

    var best: String {
        lock.lock()
        defer { lock.unlock() }
        return final.count >= last.count ? final : last
    }
}

private final class FileBufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return buffer
        }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return out
    }
}
