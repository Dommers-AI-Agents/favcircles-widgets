import SwiftUI
import PhotosUI
import FavWidgetsCore

/// The finished workout, drawn as a card for the share sheet.
struct WorkoutShareCard: View {
    let summary: WorkoutShareSummary
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(summary.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "dumbbell.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 14) {
                stat("\(max(1, summary.durationSeconds / 60))", "min")
                if !summary.exercises.isEmpty { stat("\(summary.exercises.count)", "exercises"); stat("\(summary.completedSets)", "sets") }
                if summary.cardioMinutes > 0 { stat("\(summary.cardioMinutes)", "min cardio") }
                if summary.prCount > 0 { stat("\(summary.prCount)", "PR\(summary.prCount == 1 ? "" : "s")") }
            }
            ForEach(Array(summary.exercises.prefix(6).enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text(line.bestSet + (line.isPR ? " 🏆" : "")).font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                }
            }
            ForEach(Array(summary.cardio.prefix(3).enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text(line.detail).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                }
            }
            Spacer(minLength: 4)
            Text("FavCircles").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(22)
        .frame(width: 400, alignment: .leading)
        .background(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
        }
    }

    @MainActor
    static func jpeg(summary: WorkoutShareSummary, accent: Color) -> Data? {
        #if os(iOS)
        let renderer = ImageRenderer(content: WorkoutShareCard(summary: summary, accent: accent))
        renderer.scale = 3
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}
