import SwiftUI
import FavWidgetsCore

/// Measure (camera), strap (Bluetooth), this month's readings.
struct HeartbeatFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<HeartbeatSettings>
    @ObservedObject var month: WidgetStateController<HeartbeatMonth>
    @ObservedObject var previousMonth: WidgetStateController<HeartbeatMonth>

    @StateObject private var camera = CameraPulseMonitor()
    @StateObject private var strap = HeartRateStrapMonitor()
    @State private var showMeasure = false

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WidgetSyncBadge(state: month.syncState, theme: theme)
                latestBlock
                measureBlock
                strapBlock
                monthBlock
                Text(HeartbeatCopy.disclaimer)
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await settings.loadIfNeeded()
            await month.loadIfNeeded()
            await previousMonth.loadIfNeeded()
        }
        .sheet(isPresented: $showMeasure, onDismiss: { camera.stop() }) {
            PulseMeasureView(context: context, camera: camera) { reading in
                save(reading)
            }
        }
        .onDisappear { strap.disconnect() }
    }

    private var latest: HeartReading? {
        [month.model.latest, previousMonth.model.latest].compactMap { $0 }.max { $0.at < $1.at }
    }

    // MARK: - Blocks

    private var latestBlock: some View {
        let theme = context.theme
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let latest {
                Text("\(latest.bpm)").font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(context.accent).monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text("bpm · \(HeartbeatCopy.band(bpm: latest.bpm))").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.label)
                    Text("\(latest.source.label) · \(CareCopy.relative(latest.at, calendar: context.calendar))").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
            } else {
                Text("No readings yet. Measure with the camera below, or connect a strap.")
                    .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var measureBlock: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Camera", theme: theme)
            if CameraPulseMonitor.isAvailable {
                WidgetUI.primaryButton("Measure my pulse", color: context.accent) {
                    context.track("heartbeat_measure_tap")
                    showMeasure = true
                    camera.start()
                }
                Text("Rest your fingertip lightly over the main rear camera lens (the 1× one). Hold still; it usually takes 8 to 20 seconds.")
                    .font(.system(size: 15)).foregroundStyle(theme.label).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Camera measuring needs an iPhone with a rear camera.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    private var strapBlock: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Chest strap or armband", theme: theme)
            switch strap.state {
            case .idle:
                Button { strap.scan() } label: {
                    Label("Find a strap", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
                Text("Works with Polar, Garmin, Wahoo and most straps that broadcast heart rate over Bluetooth.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
            case .scanning:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for straps… put it on so it wakes up.").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
                ForEach(strap.devices) { device in
                    Button { strap.connect(device) } label: {
                        HStack { Text(device.name).font(.system(size: 15)).foregroundStyle(theme.label); Spacer(); Text("Connect").font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent) }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                    }
                    .buttonStyle(.plain)
                }
                Button("Stop looking") { strap.disconnect() }.font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
            case .connecting(let name):
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Connecting to \(name)…").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel) }
            case .connected(let name):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(strap.bpm.map(String.init) ?? "—").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(context.accent).monospacedDigit()
                    Text("bpm · \(name)").font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                HStack(spacing: 12) {
                    if let bpm = strap.bpm {
                        Button("Save reading") {
                            save(HeartReading(at: Date(), bpm: bpm, source: .strap))
                            settings.update { $0.lastStrapName = name; $0.lastSource = .strap }
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    Button("Disconnect") { strap.disconnect() }.font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
            case .unavailable(let message):
                Text(message).font(.system(size: 13)).foregroundStyle(theme.warning)
                Button("Try again") { strap.scan() }.font(.system(size: 13, weight: .semibold)).foregroundStyle(context.accent)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private var monthBlock: some View {
        let theme = context.theme
        let readings = month.model.readings.sorted { $0.at > $1.at }
        return VStack(alignment: .leading, spacing: 8) {
            WidgetUI.header("This month", theme: theme)
            Text(HeartbeatCopy.monthLine(month.model)).font(.system(size: 14)).foregroundStyle(theme.label)
            ForEach(readings.prefix(30)) { reading in
                HStack(spacing: 10) {
                    Image(systemName: reading.source == .strap ? "antenna.radiowaves.left.and.right" : "camera.fill")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).frame(width: 18)
                    Text("\(reading.bpm) bpm").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.label).monospacedDigit()
                    Text(HeartbeatCopy.band(bpm: reading.bpm)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    Spacer()
                    Text(reading.at.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button(role: .destructive) { month.update { $0.readings.removeAll { $0.id == reading.id } } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private func save(_ reading: HeartReading) {
        let key = MonthKey(reading.at, calendar: context.calendar)
        let controller = key == context.currentMonth ? month : context.month(HeartbeatMonth.self, key)
        controller.update { $0.readings.append(reading) }
        settings.update { $0.lastSource = reading.source }
        context.track("heartbeat_saved", ["source": reading.source.rawValue, "bpm": "\(reading.bpm)"])
        context.host.haptic(.success)
    }
}

/// The measuring sheet: instructions, a progress ring, the live number and
/// the waveform. Saves on completion.
struct PulseMeasureView: View {
    let context: WidgetContext
    @ObservedObject var camera: CameraPulseMonitor
    let onSave: (HeartReading) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = context.theme
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(theme.tertiaryBackground, lineWidth: 12)
                    Circle().trim(from: 0, to: camera.progress).stroke(context.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.3), value: camera.progress)
                    VStack(spacing: 4) {
                        if case .done = camera.phase, let result = camera.result {
                            Text("\(result.bpm)").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(context.accent)
                            Text("bpm").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        } else if let bpm = camera.bpm {
                            Text("\(bpm)").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(context.accent)
                            Text("bpm · settling").font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                        } else {
                            Image(systemName: "heart.fill").font(.system(size: 44)).foregroundStyle(context.accent.opacity(0.5))
                        }
                    }
                }
                .frame(width: 220, height: 220)

                if showsGuide {
                    // Where the finger goes, and a live view that turns red
                    // when it's on the right lens.
                    HStack(spacing: 20) {
                        LensGuide(accent: context.accent, theme: theme)
                        #if os(iOS)
                        VStack(spacing: 6) {
                            CameraLiveDot(session: camera.session)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(theme.tertiaryBackground, lineWidth: 2))
                            Text("Turns red on the\nright lens").font(.system(size: 11)).foregroundStyle(theme.secondaryLabel)
                                .multilineTextAlignment(.center)
                        }
                        #endif
                    }
                } else {
                    PulseWaveform(samples: camera.waveform, color: context.accent)
                        .frame(height: 60)
                        .padding(.horizontal, 24)
                }

                Text(statusText).font(.system(size: 15)).foregroundStyle(theme.label)
                    .multilineTextAlignment(.center).padding(.horizontal, 24).fixedSize(horizontal: false, vertical: true)
                if !camera.diagnostic.isEmpty {
                    Text(camera.diagnostic).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.secondaryLabel)
                        .multilineTextAlignment(.center).padding(.horizontal, 24).fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if case .done = camera.phase, let result = camera.result {
                    VStack(spacing: 10) {
                        Text(HeartbeatCopy.band(bpm: result.bpm)).font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                        WidgetUI.primaryButton("Save reading", color: context.accent) {
                            onSave(result)
                            dismiss()
                        }
                        Button("Measure again") { camera.start() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                    }
                    .padding(.horizontal, 16)
                } else if case .failed = camera.phase {
                    Button("Try again") { camera.start() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(context.accent)
                }
                Spacer(minLength: 16)
            }
            .background(theme.background.ignoresSafeArea())
            .widgetInlineNavigationTitle("Measuring")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    /// The guide shows until a pulse is actually being read.
    private var showsGuide: Bool {
        switch camera.phase {
        case .idle, .starting, .waitingForFinger, .failed: return true
        case .measuring, .done: return false
        }
    }

    private var statusText: String {
        switch camera.phase {
        case .idle, .starting: return "Starting the camera…"
        case .waitingForFinger: return camera.diagnostic.hasSuffix("settling") ? "Got it. Adjusting to your finger…" : "Rest your fingertip lightly over the main 1× lens, top-left of the camera block. The flash lights it from the side."
        case .measuring: return camera.bpm == nil ? "Reading your pulse. Hold still…" : "Keep holding, a few more seconds…"
        case .done: return "Done."
        case .failed(let message): return message
        }
    }
}

struct PulseWaveform: View {
    let samples: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard samples.count > 1 else { return }
                let maxAbs = max(1e-6, samples.map { abs($0) }.max() ?? 1)
                let stepX = proxy.size.width / CGFloat(samples.count - 1)
                let midY = proxy.size.height / 2
                for (i, s) in samples.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * stepX, y: midY - CGFloat(s / maxAbs) * (midY - 4))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, lineWidth: 2)
        }
    }
}

/// The back of a three-lens iPhone with the main (1×) lens marked and a
/// fingertip resting on it. On every current iPhone the 1× camera is the
/// top-left lens of the block (the top one on two-lens phones).
struct LensGuide: View {
    let accent: Color
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.tertiaryBackground)
                .frame(width: 110, height: 150)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.secondaryLabel.opacity(0.25))
                .frame(width: 78, height: 78)
                .offset(x: -8, y: -28)
            // Lenses: main top-left, ultra-wide below it, telephoto right.
            lens.offset(x: -26, y: -46)
            lens.offset(x: -26, y: -10)
            lens.offset(x: 10, y: -28)
            Circle().fill(Color.yellow.opacity(0.8)).frame(width: 8, height: 8).offset(x: 30, y: -48)
            // The finger, over the main lens.
            Capsule()
                .fill(Color(red: 0.93, green: 0.72, blue: 0.60))
                .frame(width: 30, height: 84)
                .rotationEffect(.degrees(-20))
                .offset(x: -18, y: -14)
            Circle().stroke(accent, lineWidth: 3).frame(width: 34, height: 34).offset(x: -26, y: -46)
            Text("1×").font(.system(size: 11, weight: .bold)).foregroundStyle(accent).offset(x: -52, y: -46)
        }
        .accessibilityLabel("Fingertip over the main rear camera lens, top-left of the camera block")
    }

    private var lens: some View {
        Circle().fill(theme.background).frame(width: 24, height: 24)
            .overlay(Circle().fill(theme.label.opacity(0.7)).frame(width: 14, height: 14))
    }
}

#if os(iOS)
import AVFoundation
import UIKit

/// A live view of the measuring camera: black or the room until the right
/// lens is covered, then solid red. The clearest "you're on the right one".
struct CameraLiveDot: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
