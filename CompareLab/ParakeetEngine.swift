import Foundation

actor ParakeetEngine {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var waiters: [CheckedContinuation<ParakeetLine, Error>] = []
    private var queued: [ParakeetLine] = []
    private(set) var loadMs: Int?
    private var ready = false

    func warmup() async throws {
        if ready { return }
        try startProcess()
        let line = try await nextJSON()
        if line.event == "error" {
            throw makeError(line.error ?? "Parakeet failed to load")
        }
        loadMs = line.loadMs
        ready = true
    }

    func transcribe(fileURL: URL) async -> EngineResult {
        var result = EngineResult.blank(
            name: "Parakeet",
            subtitle: "TDT 0.6b · MLX · Hugging Face"
        )
        do {
            try await warmup()
            result.status = .running
            result.loadMs = loadMs
            try writeJSON(["cmd": "transcribe", "path": fileURL.path])
            let line = try await nextJSON()
            if line.event == "error" {
                throw makeError(line.error ?? "Parakeet failed")
            }
            result.transcript = (line.transcript ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.inferMs = line.latencyMs
            result.loadMs = line.loadMs ?? loadMs
            result.status = result.transcript.isEmpty ? .failed : .done
            if result.transcript.isEmpty { result.error = "Empty transcript" }
            return result
        } catch {
            result.status = .failed
            result.error = error.localizedDescription
            result.loadMs = loadMs
            return result
        }
    }

    private func startProcess() throws {
        guard let python = ParakeetPaths.python() else {
            throw makeError("Python venv missing at scripts/.venv-parakeet")
        }
        guard let script = ParakeetPaths.sidecar() else {
            throw makeError("parakeet_sidecar.py not found")
        }
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            Task { await self?.consume(chunk) }
        }
    }

    private func consume(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        while let range = stdoutBuffer.firstRange(of: Data("\n".utf8)) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<range.lowerBound)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<range.upperBound)
            guard !line.isEmpty,
                  let object = try? JSONDecoder().decode(ParakeetLine.self, from: line)
            else { continue }
            if waiters.isEmpty {
                queued.append(object)
            } else {
                waiters.removeFirst().resume(returning: object)
            }
        }
    }

    private func writeJSON(_ payload: [String: String]) throws {
        guard let stdinHandle else { throw makeError("Parakeet process is not running") }
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(Data("\n".utf8))
        try stdinHandle.write(contentsOf: data)
    }

    private func nextJSON() async throws -> ParakeetLine {
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "CompareLab.Parakeet", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

enum ParakeetPaths {
    static func python() -> URL? {
        let fm = FileManager.default
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CADENCE_PARAKEET_PYTHON"] {
            urls.append(URL(fileURLWithPath: env))
        }
        if let exe = Bundle.main.executableURL {
            var dir = exe.deletingLastPathComponent()
            for _ in 0..<14 {
                urls.append(dir.appending(path: "scripts/.venv-parakeet/bin/python"))
                urls.append(dir.appending(path: "scripts/.venv-parakeet/bin/python3.12"))
                dir.deleteLastPathComponent()
            }
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        urls.append(cwd.appending(path: "scripts/.venv-parakeet/bin/python"))
        urls.append(cwd.appending(path: "scripts/.venv-parakeet/bin/python3.12"))
        return urls.first { fm.isExecutableFile(atPath: $0.path) }
    }

    static func sidecar() -> URL? {
        if let bundled = Bundle.main.url(forResource: "parakeet_sidecar", withExtension: "py") {
            return bundled
        }
        let fm = FileManager.default
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CADENCE_PARAKEET_SIDECAR"] {
            urls.append(URL(fileURLWithPath: env))
        }
        if let exe = Bundle.main.executableURL {
            var dir = exe.deletingLastPathComponent()
            for _ in 0..<14 {
                urls.append(dir.appending(path: "CompareLab/Resources/parakeet_sidecar.py"))
                dir.deleteLastPathComponent()
            }
        }
        urls.append(
            URL(fileURLWithPath: fm.currentDirectoryPath)
                .appending(path: "CompareLab/Resources/parakeet_sidecar.py")
        )
        return urls.first { fm.fileExists(atPath: $0.path) }
    }
}
