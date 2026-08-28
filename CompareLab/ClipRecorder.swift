import AVFoundation
import Foundation

@MainActor
final class ClipRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    var isRecording: Bool { recorder?.isRecording == true }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        stop()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compare-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw NSError(
                domain: "CompareLab.Recorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not start the microphone"]
            )
        }
        self.recorder = recorder
        self.fileURL = url
    }

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return fileURL
    }
}
