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
                Text("Rest your fingertip lightly over the rear camera lens. It takes about 20 seconds; hold still.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel).fixedSize(horizontal: false, vertical: true)
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

                PulseWaveform(samples: camera.waveform, color: context.accent)
                    .frame(height: 60)
                    .padding(.horizontal, 24)

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

    private var statusText: String {
        switch camera.phase {
        case .idle, .starting: return "Starting the camera…"
        case .waitingForFinger: return camera.diagnostic.hasSuffix("settling") ? "Got it. Adjusting to your finger…" : "Rest your fingertip lightly over the rear camera lens. The flash lights it from the side."
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
