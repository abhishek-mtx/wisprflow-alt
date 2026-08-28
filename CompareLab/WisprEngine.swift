import AppKit
import Foundation

enum WisprEngine {
    private static let apiURL = URL(string: "https://platform-api.wisprflow.ai/api/v1/dash/api")!
    private static let docsURL = URL(string: "https://api-docs.wisprflow.ai/rest_api_transcribe")!
    private static let platformURL = URL(string: "https://platform.wisprflow.ai")!

    static var desktopInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Wispr Flow.app")
    }

    static var apiKey: String {
        get {
            if let env = ProcessInfo.processInfo.environment["WISPR_FLOW_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !env.isEmpty
            {
                return env
            }
            return UserDefaults.standard.string(forKey: "compare.wisprAPIKey") ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: "compare.wisprAPIKey") }
    }

    static var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func openDocs() {
        NSWorkspace.shared.open(docsURL)
    }

    static func openPlatform() {
        NSWorkspace.shared.open(platformURL)
    }

    static func openDesktopApp(activates: Bool = true) {
        let url = URL(fileURLWithPath: "/Applications/Wispr Flow.app")
        guard desktopInstalled else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    static func transcribe(fileURL: URL) async -> EngineResult {
        var result = EngineResult.blank(
            name: "Wispr Flow",
            subtitle: subtitleLine
        )
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            result.status = .failed
            result.error = noKeyMessage
            return result
        }

        result.status = .running
        let started = CFAbsoluteTimeGetCurrent()
        do {
            let data = try Data(contentsOf: fileURL)
            let audio = data.base64EncodedString()
            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 45
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(audio: audio))
            let (body, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                throw NSError(
                    domain: "CompareLab.Wispr",
                    code: status,
                    userInfo: [NSLocalizedDescriptionKey: "Wispr Flow rejected the API key (HTTP \(status)). Keys come from platform.wisprflow.ai (enterprise access)."]
                )
            }
            if status >= 400 {
                let detail = String(data: body, encoding: .utf8) ?? "HTTP \(status)"
                throw NSError(
                    domain: "CompareLab.Wispr",
                    code: status,
                    userInfo: [NSLocalizedDescriptionKey: "Wispr Flow API: \(detail.prefix(220))"]
                )
            }
            let json = (try JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let text = (json?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let reported = json?["total_time"]
            let reportedMs: Int? = {
                if let i = reported as? Int { return i }
                if let n = reported as? NSNumber { return n.intValue }
                if let d = reported as? Double { return Int(d) }
                return nil
            }()
            result.status = text.isEmpty ? .failed : .done
            result.transcript = text
            result.subtitle = "Cloud API · REST"
            result.inferMs = reportedMs ?? Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            result.loadMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000) - (result.inferMs ?? 0)
            if result.loadMs ?? 0 < 0 { result.loadMs = nil }
            if text.isEmpty { result.error = "Empty transcript from Wispr Flow" }
            return result
        } catch {
            result.status = .failed
            result.error = error.localizedDescription
            result.inferMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            return result
        }
    }

    private static var subtitleLine: String {
        if hasAPIKey { return "Cloud API · REST" }
        if desktopInstalled { return "Desktop installed · API or manual paste" }
        return "Cloud API (key required)"
    }

    private static var noKeyMessage: String {
        if desktopInstalled {
            return "No API key yet. Add one from platform.wisprflow.ai, or paste a transcript from the Wispr Flow desktop app (Option in Wispr, speak, copy result)."
        }
        return "Wispr Flow API keys are issued via platform.wisprflow.ai (enterprise access). Add a key here, or compare Cadence vs Parakeet on-device without Wispr."
    }

    /// Matches Wispr's documented REST body: https://api-docs.wisprflow.ai/rest_api_transcribe
    private static func requestBody(audio: String) -> [String: Any] {
        [
            "audio": audio,
            "language": ["en"],
            "context": [
                "app": ["type": "other"],
                "dictionary_context": [],
                "textbox_contents": [
                    "before_text": "",
                    "selected_text": "",
                    "after_text": ""
                ]
            ]
        ]
    }
}
