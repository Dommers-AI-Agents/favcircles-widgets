import SwiftUI
import FavWidgetsCore

/// Example routines on the start page (Wes, 2026-11-03): grouped rows of
/// cards you swipe through. A card opens its preview; nothing starts from
/// a single tap on the grid.
struct WorkoutTemplateGallery: View {
    let context: WidgetContext
    let onOpen: (WorkoutTemplate) -> Void

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(WorkoutTemplates.grouped, id: \.group) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                        .textCase(.uppercase)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(section.templates) { template in
                                Button { onOpen(template) } label: { card(template) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func card(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.label)
                .lineLimit(2)
            Text(WorkoutTemplateCopy.facts(template))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(context.accent)
            Text(WorkoutTemplateCopy.exerciseList(template))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryLabel)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 200, height: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.secondaryBackground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.tertiaryBackground, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

enum WorkoutTemplateCopy {
    /// "Beginner · 35 min · Gym"
    static func facts(_ template: WorkoutTemplate) -> String {
        "\(template.level.label) · \(template.minutes) min · \(template.equipment.label)"
    }

    static func exerciseList(_ template: WorkoutTemplate) -> String {
        template.routine.items
            .compactMap { item in ExerciseCatalog.builtIn.first { $0.id == item.exerciseId }?.name }
            .joined(separator: ", ")
    }
}

/// One example routine: what it is, each exercise with sets × reps and a
/// form cue, then Start or Save to my routines.
struct WorkoutTemplatePreview: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<WorkoutSettings>
    let template: WorkoutTemplate
    let onStart: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    private var theme: WidgetTheme { context.theme }
    private var alreadySaved: Bool { saved || settings.model.routines.contains { $0.name == template.name } }

    var body: some View {
        WidgetSheet(title: template.name, theme: theme) {
            List {
                VStack(alignment: .leading, spacing: 8) {
                    Text(WorkoutTemplateCopy.facts(template))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(context.accent)
                    Text(template.blurb)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(template.routine.items) { item in
                    let exercise = settings.model.exercise(id: item.exerciseId)
                    HStack(alignment: .top, spacing: 12) {
                        ExerciseThumb(url: settings.model.imageURL(for: item.exerciseId),
                                      symbolName: exercise?.symbolName ?? "dumbbell.fill",
                                      accent: context.accent, theme: theme, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(exercise?.name ?? item.exerciseId)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(theme.label)
                                Spacer()
                                Text("\(item.targetSets) × \(item.targetReps)")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.secondaryLabel)
                            }
                            if let cue = ExerciseTips.cue(for: item.exerciseId) {
                                Text(cue)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                if template.level == .beginner {
                    Label(ExerciseTips.startLight, systemImage: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryLabel)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(context.accent.opacity(0.1)))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                VStack(spacing: 10) {
                    WidgetUI.primaryButton(settings.model.activeSession == nil ? "Start this workout" : "Finish your current workout first",
                                           color: context.accent) {
                        guard settings.model.activeSession == nil else { return }
                        context.track("workout_template_started", ["template": template.name])
                        dismiss()
                        onStart(template.routine)
                    }
                    .opacity(settings.model.activeSession == nil ? 1 : 0.5)
                    Button {
                        guard !alreadySaved else { return }
                        // A copy with its own id: theirs to change
                        settings.update { $0.routines.append(Routine(name: template.name, items: template.routine.items.map {
                            RoutineItem(exerciseId: $0.exerciseId, targetSets: $0.targetSets, targetReps: $0.targetReps)
                        })) }
                        saved = true
                        context.host.haptic(.success)
                        context.track("workout_template_saved", ["template": template.name])
                    } label: {
                        Label(alreadySaved ? "In my routines" : "Save to my routines",
                              systemImage: alreadySaved ? "checkmark" : "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(context.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// "Pick one for me": where you train and how much you've lifted → the
/// routines to start with and how to run them over a week.
struct WorkoutTemplatePicker: View {
    let context: WidgetContext
    let onOpen: (WorkoutTemplate) -> Void
    @State private var equipment: WorkoutTemplate.Equipment?
    @State private var level: WorkoutTemplate.Level?

    private var theme: WidgetTheme { context.theme }

    var body: some View {
        WidgetSheet(title: "Pick one for me", theme: theme) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    question("Where will you work out?") {
                        ForEach(WorkoutTemplate.Equipment.allCases, id: \.self) { option in
                            choice(option.label, symbol: symbol(option), selected: equipment == option) { equipment = option }
                        }
                    }
                    question("How much have you lifted before?") {
                        choice("I'm new to this", symbol: "leaf.fill", selected: level == .beginner) { level = .beginner }
                        choice("I know my way around", symbol: "flame.fill", selected: level == .intermediate) { level = .intermediate }
                    }
                    if let equipment, let level {
                        let pick = WorkoutTemplates.recommend(equipment: equipment, level: level)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Try this").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.label)
                            Text(pick.plan).font(.system(size: 15)).foregroundStyle(theme.label)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(pick.templates) { template in
                                Button { onOpen(template) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(context.accent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.label)
                                            Text(WorkoutTemplateCopy.facts(template)).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.secondaryLabel)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onAppear { context.track("workout_template_picked", ["equipment": equipment.rawValue, "level": level.rawValue]) }
                    }
                }
                .padding(20)
            }
        }
    }

    private func symbol(_ equipment: WorkoutTemplate.Equipment) -> String {
        switch equipment {
        case .gym: return "dumbbell.fill"
        case .dumbbells: return "scalemass.fill"
        case .none: return "house.fill"
        }
    }

    private func question<Choices: View>(_ title: String, @ViewBuilder choices: () -> Choices) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.label)
            choices()
        }
    }

    private func choice(_ label: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            context.host.haptic(.light)
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(selected ? .white : context.accent).frame(width: 24)
                Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(selected ? .white : theme.label)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? context.accent : theme.secondaryBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
