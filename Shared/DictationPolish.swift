import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Spoken-to-written cleanup shared by Compare and Cadence.
/// Never invent sentence breaks at capital letters (that produced "and. I").
enum DictationPolish {
    enum Mode: Sendable {
        case foundationModels
        case minimal
        case raw
    }

    struct Outcome: Sendable {
        var text: String
        var polishMs: Int
        var mode: Mode
    }

    static func polish(_ raw: String) async -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(text: trimmed, polishMs: 0, mode: .raw)
        }

        let normalized = SpokenTextCleanup.normalize(trimmed)
        let started = CFAbsoluteTimeGetCurrent()

        #if canImport(FoundationModels)
        if let fm = await foundationModelsPolish(normalized) {
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            return Outcome(text: fm, polishMs: ms, mode: .foundationModels)
        }
        #endif

        // Apple STT already emitted punctuation — only light cleanup, no fake grammar.
        let minimal = SpokenTextCleanup.minimal(normalized)
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        return Outcome(text: minimal, polishMs: ms, mode: .minimal)
    }

    #if canImport(FoundationModels)
    @MainActor
    private static func foundationModelsPolishOnMain(_ text: String) async -> String? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        default:
            return nil
        }

        let session = LanguageModelSession(model: model)
        let prompt = """
        You clean spoken dictation into written text.
        Remove filler words (um, uh, like, you know) when they are not meaningful.
        Fix punctuation and capitalization without changing meaning.
        Apply mid-sentence corrections (keep the corrected intent, drop retracted words).
        Preserve proper nouns, homophones, and technical terms exactly.
        Do NOT insert periods before words like I, I'm, or after conjunctions (and, or, but).
        Return ONLY the cleaned text with no quotes or commentary.

        Dictation:
        \(text)
        """
        do {
            let response = try await session.respond(to: prompt)
            let cleaned = String(describing: response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    private static func foundationModelsPolish(_ text: String) async -> String? {
        await foundationModelsPolishOnMain(text)
    }
    #endif
}

enum SpokenTextCleanup {
    static func normalize(_ input: String) -> String {
        var text = input
        let spoken: [(String, String)] = [
            (#"(?i)\bnew\s+line\b"#, "\n"),
            (#"(?i)\bnewline\b"#, "\n"),
            (#"(?i)\bnew\s+paragraph\b"#, "\n\n"),
            (#"(?i)\bcomma\b"#, ","),
            (#"(?i)\bperiod\b"#, "."),
            (#"(?i)\bfull\s+stop\b"#, "."),
            (#"(?i)\bquestion\s+mark\b"#, "?"),
            (#"(?i)\bexclamation\s+(?:mark|point)\b"#, "!"),
        ]
        for (pattern, replacement) in spoken {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        }
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Safe fallback when Apple Intelligence is unavailable. No invented sentence breaks.
    static func minimal(_ text: String) -> String {
        var result = text
        let fillers = [#"(?i)\buh+\b"#, #"(?i)\bum+\b"#, #"(?i)\ber+\b"#, #"(?i)\byou know\b"#]
        for pattern in fillers {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        result = result.replacingOccurrences(of: #"\b(\w+)\s+\1\b"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        result = normalize(result)
        result = result.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+\."#, with: ".", options: .regularExpression)
        if let first = result.first, first.isLetter {
            result = String(first).uppercased() + result.dropFirst()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
