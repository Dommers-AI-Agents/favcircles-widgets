import Testing
import Foundation
import AVFoundation
import CoreVideo
@testable import FavWidgets

/// A real clip through the event video pipeline: 1080p in, ≤1280 px out,
/// same length, small enough for the server's cap, with a poster.
struct EventVideoPrepTests {
    /// Writes a `seconds`-long 1920×1080 clip of changing colors.
    private func makeClip(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prep-test-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1920, kCVPixelBufferHeightKey as String: 1080
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps = 30
        for frame in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pb = buffer!
            CVPixelBufferLockBaseAddress(pb, [])
            memset(CVPixelBufferGetBaseAddress(pb), Int32(frame * 4 % 255), CVPixelBufferGetDataSize(pb))
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func aClipBecomesA720pUploadWithPosters() async throws {
        let source = try await makeClip(seconds: 3)
        defer { try? FileManager.default.removeItem(at: source) }
        let seconds = try #require(await EventVideoPrep.duration(source))
        #expect(abs(seconds - 3) < 0.2)

        let prepared = try await EventVideoPrep.prepare(source)
        defer { try? FileManager.default.removeItem(at: prepared.video) }
        let out = AVURLAsset(url: prepared.video)
        let track = try #require(try await out.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(max(size.width, size.height) <= 1280)
        let outSeconds = CMTimeGetSeconds(try await out.load(.duration))
        #expect(abs(outSeconds - 3) < 0.3)
        // Server cap for 15 s is ~5.75 MB; 3 s must be far under
        let bytes = try FileManager.default.attributesOfItem(atPath: prepared.video.path)[.size] as? Int ?? 0
        #expect(bytes > 0 && bytes < 2 * 1024 * 1024)
        #expect(!prepared.poster.isEmpty)
    }
}
