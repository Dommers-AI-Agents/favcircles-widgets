import SwiftUI
import FavWidgetsCore

/// The mixer: transport and timer at the top, the sound tiles, a level
/// slider for each sound that's on, presets and saved mixes, and the
/// month's nights.
struct SleepSoundsFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<SleepSoundsSettings>
    @ObservedObject var month: WidgetStateController<SleepSoundsMonth>
    @ObservedObject var engine: SleepSoundEngine

    @State private var isNamingMix = false
    @State private var newMixName = ""

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WidgetSyncBadge(state: settings.syncState, theme: theme)
                transport
                soundsSection
                if !engine.levels.isEmpty { levelsSection }
                mixesSection
                monthSection
                Text("Keeps playing with the screen off. Play, pause and stop from the Lock Screen or Control Center. The timer fades the sound out over its last minute.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            SleepSoundsLogging.install(context: context, engine: engine)
            await settings.loadIfNeeded()
            await month.loadIfNeeded()
            SleepSoundsLogging.restore(engine: engine, from: settings.model)
        }
        .onChange(of: engine.levels) { _ in remember() }
        .onChange(of: engine.timerMinutes) { _ in remember() }
        .onChange(of: engine.masterVolume) { _ in remember() }
    }

    private func remember() {
        guard settings.hasLoaded else { return }
        SleepSoundsLogging.remember(engine: engine, settings: settings)
    }

    // MARK: - Transport

    private var transport: some View {
        let theme = context.theme
        return VStack(spacing: 14) {
            HStack(spacing: 16) {
                Button {
                    if engine.isPlaying { engine.pause() } else { engine.play() }
                    context.track(engine.isPlaying ? "sleepsounds_play" : "sleepsounds_pause")
                    context.host.haptic(.light)
                } label: {
                    ZStack {
                        Circle().fill(context.accent)
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: engine.isPlaying ? 0 : 2)
                    }
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .disabled(engine.levels.isEmpty && !engine.isPlaying)
                .opacity(engine.levels.isEmpty && !engine.isPlaying ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.mixName)
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.label).lineLimit(1)
                    Text(statusLine)
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryLabel)
                }
                Spacer()
                if engine.isPlaying {
                    Button {
                        engine.stop()
                        context.track("sleepsounds_stop")
                        context.host.haptic(.light)
                    } label: {
                        Image(systemName: "stop.fill").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(theme.secondaryLabel)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(theme.tertiaryBackground))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = engine.lastError {
                Text(error).font(.system(size: 12)).foregroundStyle(theme.danger)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                Slider(value: Binding(get: { engine.masterVolume }, set: { engine.setMasterVolume($0) }), in: 0...1)
                    .tint(context.accent)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sleep timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                HStack(spacing: 6) {
                    ForEach(SleepTimer.choices, id: \.self) { minutes in
                        let selected = engine.timerMinutes == minutes
                        Button {
                            engine.setTimer(minutes: minutes)
                            context.host.haptic(.selection)
                        } label: {
                            Text(SleepTimer.choiceText(minutes))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selected ? .white : theme.label)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Capsule().fill(selected ? context.accent : theme.tertiaryBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    private var statusLine: String {
        if engine.isPlaying {
            if let remaining = engine.remaining { return "Fades out in \(SleepTimer.remainingText(remaining))" }
            return "Playing until you stop it"
        }
        if engine.levels.isEmpty { return "Pick a sound below" }
        let n = engine.activeSoundCount
        return engine.timerMinutes > 0 ? "\(n) sound\(n == 1 ? "" : "s") · \(engine.timerMinutes) min timer" : "\(n) sound\(n == 1 ? "" : "s") · no timer"
    }

    // MARK: - Sounds

    private var soundsSection: some View {
        let theme = context.theme
        return VStack(alignment: .leading, spacing: 12) {
            WidgetUI.header("Sounds", theme: theme)
            ForEach(SleepSoundCatalog.groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryLabel)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SleepSoundCatalog.all.filter { $0.group == group }) { sound in
                            tile(sound)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ sound: SleepSound) -> some View {
        let theme = context.theme
        let level = engine.levels[sound.id] ?? 0
        let on = level > 0.001
        return Button {
            engine.toggle(sound.id)
            context.track("sleepsounds_toggle", ["sound": sound.id, "on": on ? "0" : "1"])
            context.host.haptic(.selection)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: sound.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? .white : context.accent)
                Text(sound.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .white : theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? context.accent : theme.secondaryBackground))
            .overlay(alignment: .topTrailing) {
                if on {
                    Text("\(Int((level * 100).rounded()))")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Levels

    private var levelsSection: some View {
        let theme = context.theme
        let active = SleepSoundCatalog.all.filter { (engine.levels[$0.id] ?? 0) > 0.001 }
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Levels", theme: theme)
            ForEach(active) { sound in
                HStack(spacing: 10) {
                    Image(systemName: sound.symbolName).font(.system(size: 14)).foregroundStyle(context.accent).frame(width: 22)
                    Text(sound.name).font(.system(size: 14)).foregroundStyle(theme.label).frame(width: 88, alignment: .leading)
                    Slider(value: Binding(get: { engine.levels[sound.id] ?? 0 }, set: { engine.setLevel($0, for: sound.id) }), in: 0.05...1)
                        .tint(context.accent)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
    }

    // MARK: - Mixes

    private var mixesSection: some View {
        let theme = context.theme
        let saved = settings.model.mixes
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Mixes", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(saved) { mix in
                        mixChip(mix, isSaved: true)
                    }
                    ForEach(SleepMix.builtIns) { mix in
                        mixChip(mix, isSaved: false)
                    }
                }
            }
            if isNamingMix {
                HStack(spacing: 8) {
                    TextField("Name this mix", text: $newMixName)
                        .font(.system(size: 15))
                        .padding(.horizontal, 10).frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.secondaryBackground))
                        .onSubmit { saveMix() }
                    Button("Save") { saveMix() }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                        .disabled(newMixName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { isNamingMix = false; newMixName = "" }
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryLabel)
                }
            } else if !engine.levels.isEmpty {
                Button {
                    newMixName = SleepMix.describe(levels: engine.levels)
                    isNamingMix = true
                } label: {
                    Label("Save this mix", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(context.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mixChip(_ mix: SleepMix, isSaved: Bool) -> some View {
        let theme = context.theme
        let selected = engine.mixName == mix.name && engine.levels == mix.levels
        return Button {
            engine.load(levels: mix.levels, name: mix.name)
            context.track("sleepsounds_mix", ["mix": mix.id])
            context.host.haptic(.selection)
        } label: {
            HStack(spacing: 5) {
                if isSaved { Image(systemName: "star.fill").font(.system(size: 10)) }
                Text(mix.name).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : theme.label)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(selected ? context.accent : theme.secondaryBackground))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isSaved {
                Button(role: .destructive) {
                    settings.update { $0.mixes.removeAll { $0.id == mix.id } }
                } label: { Label("Delete mix", systemImage: "trash") }
            }
        }
    }

    private func saveMix() {
        let name = newMixName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !engine.levels.isEmpty else { return }
        let mix = SleepMix(name: name, levels: engine.levels)
        settings.update { s in
            s.mixes.removeAll { $0.name == name }
            s.mixes.insert(mix, at: 0)
        }
        engine.load(levels: mix.levels, name: mix.name)
        isNamingMix = false
        newMixName = ""
        context.track("sleepsounds_mix_saved")
        context.host.haptic(.success)
    }

    // MARK: - Month

    private var monthSection: some View {
        let theme = context.theme
        let m = month.model
        return VStack(alignment: .leading, spacing: 6) {
            WidgetUI.header("This month", theme: theme)
            Text(SleepSoundsCopy.monthSummary(nights: m.nights(calendar: context.calendar), totalSeconds: m.totalSeconds))
                .font(.system(size: 14)).foregroundStyle(theme.label)
            if let last = m.sessions.last {
                Text("Last: \(last.mixName) · \(last.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(max(1, last.seconds / 60)) min")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }
        }
    }
}
