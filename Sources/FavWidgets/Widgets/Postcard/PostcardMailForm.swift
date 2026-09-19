import SwiftUI
import FavWidgetsCore

/// The "mail a printed postcard" row in Deliver to: a switch, a US address
/// form, and the plain-language money terms.
///
/// The terms are stated next to the switch rather than buried in fine print
/// because they're genuinely good news — nothing is charged until the card
/// goes to print — and because someone about to spend money deserves to read
/// the rule before they tap, not after.
///
/// Feedback lives next to the field it's about. A message at the bottom of
/// the form sits behind the keyboard while the person is typing into the very
/// field it describes, which is how a ten-digit ZIP once produced a greyed-out
/// Send and, from where they sat, no explanation at all.
struct PostcardMailForm: View {
    typealias Field = PostcardMailAddress.Field

    let theme: WidgetTheme
    let accent: Color
    let config: PostcardMail.Config
    @Binding var isOn: Bool
    @Binding var address: PostcardMailAddress
    let quote: PostcardMail.Quote?
    let quoteError: String?
    let isQuoting: Bool
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
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mail a printed postcard · \(PostcardMailOrder.price(cents: config.priceCents))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Text("We print it and put it in the mail.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            .tint(accent)

            if isOn {
                VStack(alignment: .leading, spacing: 8) {
                    field(.name, "Full name", text: $address.name, content: .name)
                    field(.line1, "Street address", text: $address.line1, content: .streetAddressLine1)
                    plainField("Apt, suite (optional)", text: $address.line2, content: .streetAddressLine2)
                    HStack(alignment: .top, spacing: 8) {
                        field(.city, "City", text: $address.city, content: .addressCity)
                        statePicker
                    }
                    field(.zip, "ZIP", text: zipBinding, content: .postalCode, numeric: true)
                }
                .onChange(of: address) { _ in onAddressSettled() }
                .onChange(of: focused) { now in
                    // Leaving a field is what makes an empty one worth flagging.
                    if let last = lastFocused, last != now { touched.insert(last) }
                    lastFocused = now
                }

                addressStatus

                Text(config.policyText ?? "Your card is only charged when the postcard goes to print, about \(config.cancelWindowMinutes) minutes after you send it. Cancel free until then.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
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
        TextField(placeholder, text: text)
            .font(.system(size: 15))
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.background))
            #if os(iOS)
            .textContentType(content.uiContentType)
            .keyboardType(numeric ? .numbersAndPunctuation : .default)
            .textInputAutocapitalization(content == .postalCode ? .characters : .words)
            #endif
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

/// Text-content hints, wrapped so this file compiles on macOS where
/// `UITextContentType` doesn't exist.
enum WidgetTextContent {
    case name, streetAddressLine1, streetAddressLine2, addressCity, postalCode

    #if os(iOS)
    var uiContentType: UITextContentType {
        switch self {
        case .name: return .name
        case .streetAddressLine1: return .streetAddressLine1
        case .streetAddressLine2: return .streetAddressLine2
        case .addressCity: return .addressCity
        case .postalCode: return .postalCode
        }
    }
    #endif
}
