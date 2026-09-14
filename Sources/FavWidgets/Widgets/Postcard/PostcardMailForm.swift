import SwiftUI
import FavWidgetsCore

/// The "mail a printed postcard" row in Deliver to: a switch, a US address
/// form, and the plain-language money terms.
///
/// The terms are stated next to the switch rather than buried in fine print
/// because they're genuinely good news — nothing is charged until the card
/// goes to print — and because someone about to spend money deserves to read
/// the rule before they tap, not after.
struct PostcardMailForm: View {
    let theme: WidgetTheme
    let accent: Color
    let config: PostcardMail.Config
    @Binding var isOn: Bool
    @Binding var address: PostcardMailAddress
    let quote: PostcardMail.Quote?
    let quoteError: String?
    let isQuoting: Bool
    let onAddressSettled: () -> Void

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
                    field("Full name", text: $address.name, content: .name)
                    field("Street address", text: $address.line1, content: .streetAddressLine1)
                    field("Apt, suite (optional)", text: $address.line2, content: .streetAddressLine2)
                    HStack(spacing: 8) {
                        field("City", text: $address.city, content: .addressCity)
                        statePicker
                    }
                    field("ZIP", text: $address.zip, content: .postalCode, numeric: true)
                }
                .onChange(of: address) { _ in onAddressSettled() }

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

    @ViewBuilder
    private var addressStatus: some View {
        if isQuoting {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking the address…") }
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
        } else if let quoteError {
            Text(quoteError).font(.system(size: 12)).foregroundStyle(theme.danger)
        } else if let quote {
            if quote.deliverable {
                // Show what will actually be printed. The postal service
                // rewrites addresses, and "that's not what I typed" is much
                // better asked now than after it's in the mail.
                Text("We'll mail to: \(quote.address.oneLine)")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("We couldn't find that address. Check it before sending.")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
            }
        }
    }

    private var statePicker: some View {
        Menu {
            ForEach(PostcardMailAddress.states, id: \.self) { code in
                Button(code) { address.state = code }
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
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, content: WidgetTextContent, numeric: Bool = false) -> some View {
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
