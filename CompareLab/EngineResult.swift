import Foundation

struct ParakeetLine: Sendable, Decodable {
    var event: String?
    var transcript: String?
    var latencyMs: Int?
    var loadMs: Int?
    var model: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case event, transcript, model, error
        case latencyMs = "latency_ms"
        case loadMs = "load_ms"
    }
}

struct EngineResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case idle
        case warming
        case running
        case done
        case failed
    }

    var name: String
    var subtitle: String
    var status: Status = .idle
    var transcript: String = ""
    var inferMs: Int?
    var loadMs: Int?
    var polishMs: Int?
    var firstPartialMs: Int?
    var error: String?

    static func blank(name: String, subtitle: String) -> EngineResult {
        EngineResult(name: name, subtitle: subtitle)
    }

    var statusLine: String {
        switch status {
        case .idle: return "Ready"
        case .warming: return "Loading…"
        case .running: return "Transcribing…"
        case .done:
            let infer = inferMs.map { "\($0) ms" } ?? "—"
            if let polish = polishMs, polish > 0 {
                return "\(infer) decode · \(polish) ms polish"
            }
            if let load = loadMs {
                return "\(infer) decode · \(load) ms load"
            }
            return "\(infer) decode"
        case .failed: return error ?? "Failed"
        }
    }
}
