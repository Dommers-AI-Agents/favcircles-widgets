import SwiftUI
import FavWidgetsCore

/// The calculator. Amounts live in local state; tip/people/toggles are
/// mirrored into settings through the controller's debounced `update`.
struct BillSplitFullView: View {
    let context: WidgetContext
    @ObservedObject var settings: WidgetStateController<BillSplitSettings>

    @State private var subtotalText = ""
    @State private var taxText = ""
    @State private var tipSelection = 18          // preset value, or `customTag`
    @State private var customTip = 18
    @State private var tipOnPreTax = true
    @State private var people = 2
    @State private var roundUp = false
    @State private var hasSeeded = false
    @State private var nearbyPlace: WidgetPlaceRef?

    private static let customTag = -1

    var body: some View {
        let theme = context.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WidgetSyncBadge(state: settings.syncState, theme: theme)
                amountsSection(theme)
                tipSection(theme)
                peopleSection(theme)
                resultsSection(theme)
                whereSection(theme)
                Color.clear.frame(height: 24)
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .widgetInlineNavigationTitle(context.descriptor.title)
        .task {
            await settings.loadIfNeeded()
            seedIfNeeded()
            nearbyPlace = await context.host.nearbyOrCurrentPlace()
        }
        .onChange(of: tipSelection) { _ in persistSettings() }
        .onChange(of: customTip) { _ in persistSettings() }
        .onChange(of: tipOnPreTax) { _ in persistSettings() }
        .onChange(of: people) { _ in persistSettings() }
        .onChange(of: roundUp) { _ in persistSettings() }
    }

    // MARK: - Derived values

    private var subtotal: Decimal { BillSplitFormatting.parseAmount(subtotalText) }
    private var tax: Decimal { BillSplitFormatting.parseAmount(taxText) }
    private var tipPercent: Int { tipSelection == Self.customTag ? customTip : tipSelection }

    private var result: BillSplitResult {
        BillSplitCalculator.split(subtotal: subtotal, tax: tax, tipPercent: tipPercent,
                                  tipOnPreTax: tipOnPreTax, people: people, roundUp: roundUp)
    }

    private var currencySymbol: String { BillSplitFormatting.currencySymbol() }

    // MARK: - Sections

    private func amountsSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Bill", theme: theme)
            amountField("Subtotal", text: $subtotalText, theme: theme)
            amountField("Tax (optional)", text: $taxText, theme: theme)
        }
    }

    private func amountField(_ title: String, text: Binding<String>, theme: WidgetTheme) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(theme.label)
            Spacer()
            Text(currencySymbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
            TextField("0.00", text: text)
                .widgetDecimalKeyboard()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.label)
                .frame(maxWidth: 140)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
    }

    private func tipSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Tip", theme: theme)
            Picker("Tip", selection: $tipSelection) {
                ForEach(BillSplitFormatting.tipPresets, id: \.self) { preset in
                    Text("\(preset)%").tag(preset)
                }
                Text("Custom").tag(Self.customTag)
            }
            .pickerStyle(.segmented)
            if tipSelection == Self.customTag {
                Stepper(value: $customTip, in: 0...50) {
                    HStack {
                        Text("Custom tip")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.label)
                        Spacer()
                        Text("\(customTip)%")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(context.accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            }
            Toggle(isOn: $tipOnPreTax) {
                Text("Tip on pre-tax amount")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.label)
            }
            .tint(context.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private func peopleSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("People", theme: theme)
            HStack(spacing: 12) {
                Text("\(people)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(context.accent)
                    .frame(minWidth: 60, alignment: .leading)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: people)
                Text(people == 1 ? "person" : "people")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.secondaryLabel)
                Spacer()
                Stepper("People", value: $people, in: 1...30)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            Toggle(isOn: $roundUp) {
                Text("Round up per person")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.label)
            }
            .tint(context.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    private func resultsSection(_ theme: WidgetTheme) -> some View {
        let result = result
        return VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Results", theme: theme)
            VStack(spacing: 10) {
                resultRow("Tip (\(tipPercent)%)", value: result.tip, theme: theme)
                resultRow("Total", value: result.total, theme: theme)
                Divider().overlay(theme.separator)
                HStack(alignment: .firstTextBaseline) {
                    Text("Per person")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    Text(BillSplitFormatting.money(result.perPerson))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(context.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                if roundUp {
                    let collected = BillSplitFormatting.totalCollected(perPerson: result.perPerson, people: people)
                    Text("Rounded up, total collected \(BillSplitFormatting.money(collected))")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.secondaryBackground))

            WidgetUI.primaryButton("Share", color: context.accent) { share(result) }
                .disabled(subtotal <= 0)
                .opacity(subtotal <= 0 ? 0.5 : 1)
        }
    }

    private func resultRow(_ title: String, value: Decimal, theme: WidgetTheme) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(theme.secondaryLabel)
            Spacer()
            Text(BillSplitFormatting.money(value))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(theme.label)
        }
    }

    @ViewBuilder
    private func whereSection(_ theme: WidgetTheme) -> some View {
        if let place = nearbyPlace {
            let isCurrent = settings.model.lastPlace?.id == place.id
            VStack(alignment: .leading, spacing: 10) {
                WidgetUI.header("Where are you?", theme: theme)
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(context.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.label)
                            .lineLimit(1)
                        if let city = place.city {
                            Text(city)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryLabel)
                        }
                    }
                    Spacer()
                    Button(isCurrent ? "Saved" : "Use") {
                        settings.update { $0.lastPlace = place }
                        context.host.haptic(.selection)
                        context.track("billsplit_place_set")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrent ? theme.secondaryLabel : context.accent)
                    .disabled(isCurrent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            }
        }
    }

    // MARK: - State

    private func seedIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true
        let model = settings.model
        if BillSplitFormatting.tipPresets.contains(model.lastTipPercent) {
            tipSelection = model.lastTipPercent
            customTip = model.lastTipPercent
        } else {
            tipSelection = Self.customTag
            customTip = min(50, max(0, model.lastTipPercent))
        }
        tipOnPreTax = model.tipOnPreTax
        people = min(30, max(1, model.defaultPeople))
        roundUp = model.roundUp
    }

    private func persistSettings() {
        guard hasSeeded else { return }
        let tip = tipPercent
        let people = people
        let tipOnPreTax = tipOnPreTax
        let roundUp = roundUp
        settings.update {
            $0.lastTipPercent = tip
            $0.defaultPeople = people
            $0.tipOnPreTax = tipOnPreTax
            $0.roundUp = roundUp
        }
    }

    private func share(_ result: BillSplitResult) {
        let text = BillSplitFormatting.shareText(subtotal: subtotal, tax: tax, tipPercent: tipPercent,
                                                 result: result, people: people)
        context.track("billsplit_shared", ["people": "\(people)", "tip_percent": "\(tipPercent)"])
        context.host.share([.text(text)])
    }
}
