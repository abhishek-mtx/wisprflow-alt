import Foundation

enum CadenceLog {
    private static let queue = DispatchQueue(label: "com.cadence.dictation.log")

    private static var logURL: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Cadence", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cadence.debug.log")
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func debug(_ message: String) {
        #if DEBUG
        write("DEBUG", message)
        #endif
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        defer { try? handle.close() }
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: logURL)
                }
            }
        }
        #if DEBUG
        print("[Cadence] \(message)")
        #endif
    }

    static var logPath: String { logURL.path }
}
