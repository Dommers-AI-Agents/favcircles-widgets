import Testing
import AVFoundation
import FavWidgetsCore
@testable import FavWidgets

/// The real recordings behind the nature sounds and the heartbeat
/// (2026-10-19): all present, readable, long enough to loop unnoticed.
struct SleepRecordingsTests {
    @Test func natureSoundsAndHeartbeatAreRecordedNoiseAndFanAreNot() {
        let recorded: Set<SleepSoundKind> = [.rain, .thunder, .ocean, .stream, .wind, .crickets, .fire, .heartbeat]
        #expect(SleepRecordings.available == recorded)
    }

    @Test func eachRecordingDecodesAndRunsLongEnough() throws {
        for kind in SleepRecordings.available {
            let url = try #require(SleepRecordings.url(for: kind))
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            #expect(seconds >= 45, "\(kind) is only \(seconds) s")
            #expect(file.processingFormat.channelCount >= 1)
        }
    }

    /// The loop's last moment runs into its first without a jump (the seam
    /// is a crossfade, so the two ends sit close in level)
    @Test func loopEndsMeetAtSimilarLevels() throws {
        for kind in SleepRecordings.available {
            let file = try AVAudioFile(forReading: #require(SleepRecordings.url(for: kind)))
            let rate = file.processingFormat.sampleRate
            let window = AVAudioFrameCount(rate * 0.25)
            func rms(at frame: AVAudioFramePosition) throws -> Float {
                file.framePosition = frame
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: window))
                try file.read(into: buffer, frameCount: window)
                let data = try #require(buffer.floatChannelData)[0]
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
                return (sum / Float(max(1, buffer.frameLength))).squareRoot()
            }
            let start = try rms(at: 0)
            let end = try rms(at: file.length - AVAudioFramePosition(window))
            let ratio = max(start, end) / max(1e-6, min(start, end))
            // The heartbeat's ends sit between beats; ambiences stay within ~2x
            #expect(kind == .heartbeat || ratio < 2.5, "\(kind): start \(start) vs end \(end)")
        }
    }
}
