import Accelerate
import AVFoundation
import Foundation
import Observation

enum AudioMeter {
    static let bandCount = 28

    /// RMS windows across the buffer, smoothed so bars move like Wispr's Flow Bar.
    static func bands(from buffer: AVAudioPCMBuffer, smoothing: inout [Float]) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return smoothing }
        let frames = Int(buffer.frameLength)
        guard frames >= bandCount else { return smoothing }
        if smoothing.count != bandCount {
            smoothing = Array(repeating: 0.12, count: bandCount)
        }

        let slice = max(1, frames / bandCount)
        var out = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let start = i * slice
            let len = vDSP_Length(min(slice, frames - start))
            var rms: Float = 0
            vDSP_rmsqv(channel.advanced(by: start), 1, &rms, len)
            let scaled = min(1, max(0, rms * 8))
            out[i] = smoothing[i] * 0.5 + scaled * 0.5
        }
        smoothing = out
        return out
    }
}

/// Live mic levels for the Flow Bar. Updated on the main actor from the audio tap.
@MainActor
@Observable
final class AudioMeterStore {
    static let shared = AudioMeterStore()

    var levels: [Float] = Array(repeating: 0.12, count: AudioMeter.bandCount)

    func reset() {
        levels = Array(repeating: 0.12, count: AudioMeter.bandCount)
    }

    func primeIdle() {
        levels = (0..<AudioMeter.bandCount).map { index in
            0.22 + 0.18 * abs(sin(Float(index) * 0.55))
        }
    }
}
