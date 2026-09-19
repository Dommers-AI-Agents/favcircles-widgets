import SwiftUI
import FavWidgetsCore

/// A US mailing address, checked against the postal service as it is typed.
/// Shared by the postcard's "mail a printed card" row and Fridge Mail's
/// grandparent sheet, so both say the same things in the same places.
///
/// Feedback lives next to the field it's about. A message at the bottom of
/// the form sits behind the keyboard while the person is typing into the very
/// field it describes, which is how a ten-digit ZIP once produced a greyed-out
/// Send and, from where they sat, no explanation at all.
///
/// When the postal service finds a different place from the one typed, the
/// corrected address is shown and nothing is saved or sent until the person
/// either accepts it or fixes what they typed.
struct MailAddressForm: View {
    typealias Field = PostcardMailAddress.Field

    let theme: WidgetTheme
    let accent: Color
    @Binding var address: PostcardMailAddress
    let quote: PostcardMail.Quote?
    let quoteError: String?
    let isQuoting: Bool
    /// The name is part of the address for the postcard; Fridge Mail asks
    /// for it separately with the relation, so it can hide the field.
    var showsName = true
    let onAddressSettled: () -> Void
    /// The person accepted the postal service's corrected address.
    let onAcceptCorrection: () -> Void

    @FocusState private var focused: Field?
    /// Fields the person has been in and left. An empty field they haven't
    /// reached yet is simply not filled in; an empty field they've moved past
    /// is something to point at.
    @State private var touched: Set<Field> = []
    /// Where focus was a moment ago, kept as state rather than inferred from a
    /// closure capture — that inference depends on when SwiftUI built the
    /// closure, and "probably the previous render" is not a guarantee.
    @State private var lastFocused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsName {
                field(.name, "Full name", text: $address.name, content: .name)
            }
            field(.line1, "Street address", text: $address.line1, content: .streetAddressLine1)
            plainField("Apt, suite (optional)", text: $address.line2, content: .streetAddressLine2)
            HStack(alignment: .top, spacing: 8) {
                field(.city, "City", text: $address.city, content: .addressCity)
                statePicker
            }
            field(.zip, "ZIP", text: zipBinding, content: .postalCode, numeric: true)

            addressStatus
        }
        .onChange(of: address) { _ in onAddressSettled() }
        .onChange(of: focused) { now in
            // Leaving a field is what makes an empty one worth flagging.
            if let last = lastFocused, last != now { touched.insert(last) }
            lastFocused = now
        }
    }

    /// True once the postal service has confirmed the typed address (or the
    /// person accepted its correction): what's in the fields is what prints.
    static func isSettled(_ address: PostcardMailAddress, quote: PostcardMail.Quote?) -> Bool {
        guard let quote, quote.deliverable else { return false }
        return !quote.address.differsMaterially(from: address)
    }

    // MARK: - Address check result

    @ViewBuilder
    private var addressStatus: some View {
        if isQuoting {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking the address…") }
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        } else if let quoteError {
            Text("We couldn't check that address: \(quoteError)")
                .font(.system(size: 12)).foregroundStyle(theme.danger)
        } else if let quote {
            if !quote.deliverable {
                Text("We couldn't find that address. Check the street, city, state and ZIP.")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
            } else if quote.address.differsMaterially(from: address) {
                correctionPrompt(quote.address)
            } else {
                // Same place, tidied up. Show what will actually print.
                Text("We'll mail to: \(quote.address.oneLine)")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The postal service found a different place from the one typed. It
    /// might be a typo they'd want fixed or the wrong address entirely —
    /// either way, the card waits until they've looked at it.
    private func correctionPrompt(_ corrected: PostcardMailAddress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text("That's not quite the address we found.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Text("You typed \(address.normalized.city), \(address.normalized.state) \(address.zip5). The postal service has this street at:")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(corrected.oneLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button(action: onAcceptCorrection) {
                    Text("Use this address")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
                Text("or fix what you typed above")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.danger.opacity(0.10)))
    }

    // MARK: - Fields

    private var statePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(PostcardMailAddress.states, id: \.self) { code in
                    Button(code) { address.state = code; touched.insert(.state) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(address.state.isEmpty ? "State" : address.state)
                        .foregroundStyle(address.state.isEmpty ? theme.secondaryLabel : theme.label)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .font(.system(size: 15))
                .frame(width: 78, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.background))
                .overlay(border(for: .state))
            }
            if let problem = inlineProblem(.state) {
                Text(problem).font(.system(size: 11)).foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A required field: the input, plus its problem right underneath when
    /// there is one.
    private func field(_ key: Field, _ placeholder: String, text: Binding<String>,
                       content: WidgetTextContent, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            plainField(placeholder, text: text, content: content, numeric: numeric)
                .focused($focused, equals: key)
                .overlay(border(for: key))
            if let problem = inlineProblem(key) {
                Text(problem).font(.system(size: 11)).foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func plainField(_ placeholder: String, text: Binding<String>, content: WidgetTextContent, numeric: Bool = false) -> some View {
        WidgetUI.textField(placeholder, text: text, theme: theme, fill: theme.background, content: content,
                           numeric: numeric, capitalizeAll: content == .postalCode)
    }

    @ViewBuilder
    private func border(for key: Field) -> some View {
        if inlineProblem(key) != nil {
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.danger, lineWidth: 1)
        }
    }

    /// When a field's problem is worth showing.
    ///
    /// Something typed and wrong (a seven-digit ZIP) is flagged at once.
    /// Something empty is flagged only once the person has moved past it —
    /// either by leaving that field or by reaching a later one — so a fresh
    /// form isn't a wall of red before they've typed a character.
    private func inlineProblem(_ key: Field) -> String? {
        if key == .name && !showsName { return nil }
        guard let problem = address.problem(for: key) else { return nil }
        if !address.value(for: key).isEmpty { return problem }
        let order = Field.allCases
        let position = order.firstIndex(of: key) ?? 0
        let movedPast = touched.contains { (order.firstIndex(of: $0) ?? 0) >= position }
        return movedPast ? problem : nil
    }

    /// Digits and one hyphen, ten characters at most: enough for ZIP+4, not
    /// enough for the phone number people sometimes type here by reflex.
    private var zipBinding: Binding<String> {
        Binding(
            get: { address.zip },
            set: { address.zip = String($0.filter { $0.isNumber || $0 == "-" }.prefix(10)) }
        )
    }
}
