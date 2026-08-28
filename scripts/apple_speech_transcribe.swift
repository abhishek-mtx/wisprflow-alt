import AVFoundation
import Foundation
import Speech

/// File transcriber using the same macOS 26 SpeechAnalyzer + SpeechTranscriber stack as Cadence.
@main
struct AppleSpeechTranscribe {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: apple-speech-transcribe <audio-path> [locale]\n".utf8))
            Foundation.exit(2)
        }
        let path = args[1]
        let localeID = args.count >= 3 ? args[2] : "en-US"
        do {
            let payload = try await transcribe(path: path, localeID: localeID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(payload))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            let payload = ResultPayload(
                engine: "apple-speech-transcriber",
                transcript: "",
                latencyMs: 0,
                firstPartialMs: nil,
                audioSeconds: 0,
                rtf: 0,
                error: error.localizedDescription
            )
            let encoder = JSONEncoder()
            FileHandle.standardOutput.write((try? encoder.encode(payload)) ?? Data("{}".utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func transcribe(path: String, localeID: String) async throws -> ResultPayload {
        guard FileManager.default.fileExists(atPath: path) else {
            throw makeError("file not found: \(path)")
        }
        let started = CFAbsoluteTimeGetCurrent()
        let locale = Locale(identifier: localeID.replacingOccurrences(of: "_", with: "-"))
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw makeError("asset install: \(error.localizedDescription)")
        }

        let source: AVAudioFile
        do {
            source = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        } catch {
            throw makeError("AVAudioFile: \(error.localizedDescription)")
        }
        let audioSeconds = Double(source.length) / source.processingFormat.sampleRate

        let file = source

        let firstPartialBox = FirstPartialBox()
        let textBox = TextBox()
        let resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if firstPartialBox.ms == nil, !text.isEmpty {
                        firstPartialBox.ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                    }
                    textBox.last = text
                    if result.isFinal {
                        textBox.final = text
                    }
                }
            } catch {
                textBox.error = error.localizedDescription
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.prepareToAnalyze(in: file.processingFormat)
        } catch {
            throw makeError("prepare: \(error.localizedDescription)")
        }
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } catch {
            throw makeError("start: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(2.0)
        while textBox.final.isEmpty && textBox.last.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        resultsTask.cancel()
        withExtendedLifetime(analyzer) {}

        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        let transcript = (textBox.final.isEmpty ? textBox.last : textBox.final)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isEmpty, let err = textBox.error {
            throw makeError("results: \(err)")
        }
        return ResultPayload(
            engine: "apple-speech-transcriber",
            transcript: transcript,
            latencyMs: latencyMs,
            firstPartialMs: firstPartialBox.ms,
            audioSeconds: audioSeconds,
            rtf: audioSeconds > 0 ? (Double(latencyMs) / 1000.0) / audioSeconds : 0,
            error: nil
        )
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: "Cadence.AppleSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class FirstPartialBox: @unchecked Sendable {
    var ms: Int?
}

final class TextBox: @unchecked Sendable {
    var last = ""
    var final = ""
    var error: String?
}

struct ResultPayload: Codable {
    var engine: String
    var transcript: String
    var latencyMs: Int
    var firstPartialMs: Int?
    var audioSeconds: Double
    var rtf: Double
    var error: String?

    enum CodingKeys: String, CodingKey {
        case engine
        case transcript
        case latencyMs = "latency_ms"
        case firstPartialMs = "first_partial_ms"
        case audioSeconds = "audio_seconds"
        case rtf
        case error
    }
}
