import SwiftUI
import FavWidgetsCore

/// Reorder and enable/disable widgets. Presented by the app as a sheet.
public struct WidgetManageView: View {
    @ObservedObject var model: WidgetsTabModel
    @ObservedObject private var prefs: WidgetStateController<WidgetPreferences>

    public init(model: WidgetsTabModel) {
        self.model = model
        self.prefs = model.prefs
    }

    public var body: some View {
        let theme = model.theme
        List {
            Section {
                ForEach(model.ordered) { descriptor in
                    HStack(spacing: 12) {
                        Image(systemName: descriptor.symbolName)
                            .foregroundStyle(Color(hex: descriptor.accentHex))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(descriptor.title).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.label)
                            Text(descriptor.subtitle).font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { prefs.model.isEnabled(descriptor) },
                            set: { model.setEnabled($0, id: descriptor.id) }
                        ))
                        .labelsHidden()
                        .tint(theme.primary)
                    }
                }
                .onMove { source, destination in model.move(from: source, to: destination) }
            } header: {
                Text("Drag to reorder")
            } footer: {
                Text("Your layout syncs to every device you use.")
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
        #endif
    }
}
