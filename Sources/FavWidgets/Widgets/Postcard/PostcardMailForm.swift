import SwiftUI
import FavWidgetsCore

/// The "mail a printed postcard" row in Deliver to: a switch, the shared US
/// address form (`MailAddressForm`), and the plain-language money terms.
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
    /// The person accepted the postal service's corrected address.
    let onAcceptCorrection: () -> Void

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
                MailAddressForm(theme: theme, accent: accent, address: $address, quote: quote, quoteError: quoteError,
                                isQuoting: isQuoting, onAddressSettled: onAddressSettled, onAcceptCorrection: onAcceptCorrection)

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
}
