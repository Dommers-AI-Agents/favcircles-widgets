import Foundation
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO
import FavWidgetsCore

/// A video picked from the library, copied somewhere we can read it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("event-pick-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Getting a clip ready for an event (2026-10-10): its length, a 720p H.264
/// copy at a bitrate the server's size cap allows (~1.6 Mbit/s video +
/// 96 kbit/s audio, so a 60 s clip is ~13 MB), and poster frames.
enum EventVideoPrep {
    static let maxSide: CGFloat = 1280
    static let videoBitrate = 1_600_000
    static let audioBitrate = 96_000

    struct Prepared {
        let video: URL
        let poster: Data
        let thumb: Data?
    }

    enum PrepError: Error { case unreadable, exportFailed }

    /// Seconds, or nil when the file can't be read.
    static func duration(_ url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration), time.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds > 0 ? seconds : nil
    }

    static func prepare(_ url: URL) async throws -> Prepared {
        let output = try await transcode(url)
        guard let poster = await frame(url, maxSide: 1080, quality: 0.8) else { throw PrepError.unreadable }
        return Prepared(video: output, poster: poster, thumb: await frame(url, maxSide: 320, quality: 0.7))
    }

    /// A JPEG of the clip's first moment, upright.
    static func frame(_ url: URL, maxSide: CGFloat, quality: CGFloat) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        let at = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let image = try? await generator.image(at: at).image else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Re-encodes to ≤1280 px H.264 + AAC in an MP4, keeping orientation.
    static func transcode(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw PrepError.unreadable }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let natural = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let scale = min(1, maxSide / max(natural.width, natural.height, 1))
        // Even dimensions keep H.264 happy
        let width = Int((natural.width * scale / 2).rounded()) * 2
        let height = Int((natural.height * scale / 2).rounded()) * 2

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("event-video-\(UUID().uuidString).mp4")
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)

        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(out)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: audioBitrate
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioOut = out
            audioIn = input
        }

        guard reader.startReading(), writer.startWriting() else { throw PrepError.exportFailed }
        writer.startSession(atSourceTime: .zero)

        let box = WriterBox(reader: reader, writer: writer)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await pump(videoOut, into: videoIn, label: "event-video-v", box: box) }
            if let audioOut, let audioIn {
                group.addTask { await pump(audioOut, into: audioIn, label: "event-video-a", box: box) }
            }
        }
        guard reader.status == .completed else {
            writer.cancelWriting()
            throw PrepError.exportFailed
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        guard writer.status == .completed else { throw PrepError.exportFailed }
        return outURL
    }

    /// Lets the pump closures share the reader/writer across queues.
    private final class WriterBox: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        init(reader: AVAssetReader, writer: AVAssetWriter) { self.reader = reader; self.writer = writer }
    }

    /// Copies one track's samples until it runs out, then marks it finished.
    private static func pump(_ output: AVAssetReaderTrackOutput, into input: AVAssetWriterInput,
                             label: String, box: WriterBox) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: label)
            var finished = false
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData && !finished {
                    if box.writer.status == .failed || box.reader.status == .failed {
                        finished = true
                    } else if let sample = output.copyNextSampleBuffer() {
                        if !input.append(sample) { finished = true }
                        continue
                    } else {
                        finished = true
                    }
                }
                if finished {
                    input.markAsFinished()
                    done.resume()
                }
            }
        }
    }

    /// PUTs a file to a signed Cloud Storage URL.
    static func put(_ file: URL, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        try check(response)
    }

    static func put(_ data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        try check(response)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WidgetAPIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Upload failed")
        }
    }
}
