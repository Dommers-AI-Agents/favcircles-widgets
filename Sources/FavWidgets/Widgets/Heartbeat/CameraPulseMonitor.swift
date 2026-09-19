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

    /// Seconds of clean signal before a reading is final.
    let measureSeconds: Double = 20
    private var estimator = HeartRateEstimator(sampleRate: 30, windowSeconds: 8)
    private var fingerSince: Double?
    private var startTime: Double?
    private var frameCount = 0
    private var bpmHistory: [Int] = []

    #if os(iOS)
    private let session = AVCaptureSession()
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
                if device.hasTorch { try device.setTorchModeOn(level: 0.3) }
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
    fileprivate func ingest(red: Double, green: Double, blue: Double, time: Double) {
        guard phase == .waitingForFinger || phase == .measuring else { return }
        let covered = HeartRateEstimator.isFingerCovering(meanRed: red, meanGreen: green, meanBlue: blue)
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
            }
            return
        }
        if fingerSince == nil {
            fingerSince = time
            #if os(iOS)
            lockExposureIfNeeded()
            #endif
        }
        // Give the exposure lock a moment to settle before trusting frames.
        guard let since = fingerSince, time - since > 0.6 else { return }
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
        if time - startTime >= measureSeconds {
            finish()
        }
    }

    private func finish() {
        guard let bpm, bpmHistory.count >= 4 else {
            phase = .failed("Couldn't find a steady pulse. Hold your fingertip gently but fully over the lens and flash, and keep still.")
            stop()
            return
        }
        result = HeartReading(at: Date(), bpm: bpm, source: .camera, confidence: confidence)
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
