import Foundation
import Combine
import FavWidgetsCore
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// Reads a pulse from a fingertip pressed over the rear camera and flash.
/// Each frame's mean red level rises and falls with blood volume; the
/// estimator in Core turns that into beats per minute.
///
/// The one thing that makes or breaks this: exposure and white balance are
/// locked once the finger is on, otherwise the camera's auto-exposure
/// cancels the very variation being measured.
@MainActor
final class CameraPulseMonitor: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, starting, waitingForFinger, measuring, done, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var bpm: Int?
    @Published private(set) var confidence: Double = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var waveform: [Double] = []
    @Published private(set) var result: HeartReading?
    /// One line of numbers for the measuring sheet: what the camera sees and
    /// how sure the estimator is. The only way to tell "no finger" from
    /// "saturated" from "noisy" on a phone you can't see.
    @Published private(set) var diagnostic: String = ""
    /// What the camera sees right now, as 0…1 red/green/blue: the sheet's
    /// "you're on the right lens" dot. Comes from the same frames the pulse
    /// is read from, so it can't disagree with the detection.
    @Published private(set) var frameRGB: [Double] = [0, 0, 0]

    /// Longest a measurement runs; it ends sooner once the number is steady.
    let measureSeconds: Double = 20
    /// Shortest: the estimator needs a full window plus a few agreeing reads.
    let minSeconds: Double = 8
    private var estimator = HeartRateEstimator(sampleRate: 30, windowSeconds: 8)
    private var fingerSince: Double?
    private var startTime: Double?
    private var frameCount = 0
    private var bpmHistory: [Int] = []
    /// Frames since the exposure lock in which red was pinned at the top.
    private var saturatedFrames = 0
    private var saturationRetries = 0
    private var torchLevel: Float = 0.3
    private var framesSeen = 0

    #if os(iOS)
    /// The running capture session, for the sheet's small live view (it
    /// turns red when the right lens is covered).
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.favcircles.widgets.pulse", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var locked = false
    #endif

    static var isAvailable: Bool {
        #if os(iOS)
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #else
        return false
        #endif
    }

    func start() {
        guard phase == .idle || phase == .done || { if case .failed = phase { return true }; return false }() else { return }
        phase = .starting
        result = nil
        bpm = nil
        confidence = 0
        progress = 0
        waveform = []
        bpmHistory = []
        fingerSince = nil
        startTime = nil
        frameCount = 0
        saturatedFrames = 0
        saturationRetries = 0
        torchLevel = 0.3
        framesSeen = 0
        diagnostic = ""
        frameRGB = [0, 0, 0]
        estimator.reset()
        #if os(iOS)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.phase = .failed("Allow camera access in Settings to measure your pulse."); return }
                self.configureAndRun()
            }
        }
        #else
        phase = .failed("Camera measuring needs an iPhone.")
        #endif
    }

    func stop() {
        #if os(iOS)
        let session = self.session
        let device = self.device
        queue.async {
            if session.isRunning { session.stopRunning() }
            if let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                device.unlockForConfiguration()
            }
        }
        locked = false
        #endif
        if phase != .done, case .failed = phase {} else if phase != .done { phase = .idle }
    }

    #if os(iOS)
    private func configureAndRun() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            phase = .failed("No rear camera on this device.")
            return
        }
        self.device = device
        let session = self.session
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        queue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .low
            for input in session.inputs { session.removeInput(input) }
            for out in session.outputs { session.removeOutput(out) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
                if session.canAddOutput(output) { session.addOutput(output) }
                try device.lockForConfiguration()
                // 30 fps is plenty for a pulse and keeps the phone cool.
                if let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                    _ = range
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                }
                if device.hasTorch { try device.setTorchModeOn(level: self?.initialTorchLevel ?? 0.3) }
                device.unlockForConfiguration()
            } catch {
                session.commitConfiguration()
                Task { @MainActor in self?.phase = .failed("Couldn't start the camera: \(error.localizedDescription)") }
                return
            }
            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor in self?.phase = .waitingForFinger }
        }
    }

    /// Lock exposure and white balance the moment a finger is detected, so
    /// the camera stops compensating for the pulse.
    private func lockExposureIfNeeded() {
        guard !locked, let device else { return }
        locked = true
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()
        }
    }

    /// Read from the capture queue at session start; the main-actor value is
    /// always 0.3 there.
    private nonisolated var initialTorchLevel: Float { 0.3 }

    /// Never above half power: full torch for more than a moment trips the
    /// phone's thermal protection, which switches the torch OFF mid-measure.
    /// Half is plenty to light a fingertip.
    static let maxTorch: Float = 0.5

    private func setTorch(level: Float) {
        guard let device, device.hasTorch else { return }
        let clamped = max(0.05, min(Self.maxTorch, level))
        torchLevel = clamped
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            try? device.setTorchModeOn(level: clamped)
            device.unlockForConfiguration()
        }
    }

    private func unlockExposure() {
        guard locked, let device else { return }
        locked = false
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
        }
    }
    #endif

    /// One frame's colour, from the capture queue.
    ///
    /// Order matters here and was wrong once: the exposure used to be locked
    /// the instant a finger was seen, which froze the *room's* exposure with a
    /// torch behind a fingertip. Red pinned at 255, the frame was flat, and
    /// there was no pulse to find. Now: finger seen → let auto-exposure adapt
    /// (0.8 s) → lock → let the lock settle (0.5 s) → measure.
    fileprivate func ingest(red: Double, green: Double, blue: Double, time: Double) {
        guard phase == .waitingForFinger || phase == .measuring else { return }
        let covered = HeartRateEstimator.isFingerCovering(meanRed: red, meanGreen: green, meanBlue: blue)
        framesSeen += 1
        if framesSeen % 3 == 0 {
            frameRGB = [red / 255, green / 255, blue / 255]
        }
        #if os(iOS)
        // The system can switch the torch off (heat, a phone call). Relight
        // it as soon as it's allowed again; say so meanwhile.
        var torchNote = ""
        if framesSeen % 15 == 0, let device, device.hasTorch, !device.isTorchActive {
            if device.isTorchAvailable { setTorch(level: torchLevel) } else { torchNote = " · torch off (phone warm?)" }
        }
        #else
        let torchNote = ""
        #endif
        if framesSeen % 6 == 0 {
            diagnostic = String(format: "red %.0f · green %.0f · blue %.0f · torch %.2f · confidence %.2f · %@%@",
                                red, green, blue, torchLevel, confidence, phaseLabel, torchNote)
        }
        if !covered {
            if phase == .measuring {
                // Finger lifted: start over, but keep the session warm.
                phase = .waitingForFinger
                estimator.reset()
                fingerSince = nil
                startTime = nil
                bpmHistory = []
                progress = 0
                bpm = nil
                #if os(iOS)
                unlockExposure()
                #endif
            } else {
                fingerSince = nil
            }
            return
        }
        if fingerSince == nil { fingerSince = time; saturatedFrames = 0 }
        guard let since = fingerSince else { return }
        #if os(iOS)
        // Let auto-exposure adapt to the finger before freezing it.
        if time - since > 0.8 { lockExposureIfNeeded() }
        guard locked, time - since > 1.3 else { return }
        // Locked but pinned at the top: the torch is too bright for this
        // finger. Dim it and let AE re-settle, up to twice.
        if red > 250 {
            saturatedFrames += 1
            if saturatedFrames >= 15, saturationRetries < 2 {
                saturationRetries += 1
                saturatedFrames = 0
                setTorch(level: torchLevel * 0.35)
                unlockExposure()
                fingerSince = time
                if phase == .measuring {
                    phase = .waitingForFinger
                    estimator.reset(); startTime = nil; bpmHistory = []; progress = 0; bpm = nil
                }
                return
            }
        } else {
            saturatedFrames = 0
        }
        #else
        guard time - since > 1.3 else { return }
        #endif
        if phase == .waitingForFinger {
            phase = .measuring
            startTime = time
            estimator.reset()
        }
        estimator.add(value: red, at: time)
        frameCount += 1
        guard let startTime else { return }
        progress = min(1, (time - startTime) / measureSeconds)
        if frameCount % 3 == 0 {
            waveform = Array(estimator.waveform.suffix(150))
            if let estimate = estimator.estimate() {
                confidence = estimate.confidence
                if estimate.confidence > 0.3 {
                    bpmHistory.append(estimate.bpm)
                    if bpmHistory.count > 12 { bpmHistory.removeFirst() }
                    bpm = Int((Double(bpmHistory.reduce(0, +)) / Double(bpmHistory.count)).rounded())
                }
            }
        }
        // Done when the number has settled, or at the cap either way.
        let steady = time - startTime >= minSeconds && confidence >= 0.5 && HeartRateEstimator.isSteady(bpmHistory)
        if steady || time - startTime >= measureSeconds {
            finish()
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle: return "idle"
        case .starting: return "starting"
        case .waitingForFinger: return fingerSince == nil ? "no finger" : "settling"
        case .measuring: return "measuring"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    private func finish() {
        guard let bpm, bpmHistory.count >= 4 else {
            phase = .failed("Couldn't find a steady pulse. Rest your fingertip lightly over the rear camera lens, don't press hard, and keep still.")
            stop()
            return
        }
        result = HeartReading(at: Date(), bpm: bpm, source: .camera, confidence: confidence)
        progress = 1
        phase = .done
        stop()
    }
}

#if os(iOS)
extension CameraPulseMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        // Sample every 8th pixel of every 8th row: ~1/64 of the frame, more
        // than enough for a mean, and cheap enough for 30 fps.
        var r = 0, g = 0, b = 0, n = 0
        var y = 0
        while y < height {
            let row = bytes + y * bytesPerRow
            var x = 0
            while x < width {
                let p = row + x * 4
                b += Int(p[0]); g += Int(p[1]); r += Int(p[2])
                n += 1
                x += 8
            }
            y += 8
        }
        guard n > 0 else { return }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let red = Double(r) / Double(n), green = Double(g) / Double(n), blue = Double(b) / Double(n)
        Task { @MainActor [weak self] in self?.ingest(red: red, green: green, blue: blue, time: time) }
    }
}
#endif
