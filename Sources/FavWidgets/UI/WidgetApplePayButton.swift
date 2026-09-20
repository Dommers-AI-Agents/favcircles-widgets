import SwiftUI
import FavWidgetsCore
#if os(iOS)
import PassKit
#endif

/// Apple's own button, for every place the widgets take money.
///
/// Guideline 4.9 wants Apple's asset and Apple's wording wherever Apple Pay is
/// a purchase option. A custom-coloured button that happens to open the Apple
/// Pay sheet is a rejection — that is what happened to 1.3.3 (4), where the
/// reviewer tapped a red "Send postcard" and landed in Wallet setup having
/// never seen an Apple Pay button.
///
/// The type adapts to the Wallet. With no card — a fresh review device, which
/// is exactly what App Review used — it reads "Set up Apple Pay", so the
/// button names what the tap will actually do instead of promising a purchase
/// it can only redirect. The action is unchanged in both states: the host
/// already sends an empty Wallet to `openPaymentSetup`.
public struct WidgetApplePayButton: View {
    public enum Purchase {
        /// A cart that may hold more than the paid item — the postcard Send
        /// also delivers digitally, so "Check out" reads truer than "Buy".
        case checkOut
        /// One thing, bought outright (a pack of cards).
        case buy
        /// A recurring plan (Fridge Mail monthly).
        case subscribe
    }

    private let purchase: Purchase
    private let action: () -> Void
    /// `.disabled()` does not reach a represented UIKit view on its own, so it
    /// is read here and applied by hand below.
    @Environment(\.isEnabled) private var isEnabled

    public init(_ purchase: Purchase, action: @escaping () -> Void) {
        self.purchase = purchase
        self.action = action
    }

    #if os(iOS)
    public var body: some View {
        Representable(type: resolvedType, isEnabled: isEnabled, action: action)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            // PKPaymentButton's type is fixed at init, so a Wallet that gains
            // its first card while this is on screen needs a new view.
            .id(resolvedType.rawValue)
    }

    /// `canMakePayments()` asks whether the device could pay; this asks whether
    /// there is a card to pay with. The two differ on every fresh device.
    private var resolvedType: PKPaymentButtonType {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: PKPaymentRequest.availableNetworks())
            ? purchase.buttonType
            : .setUp
    }

    private struct Representable: UIViewRepresentable {
        let type: PKPaymentButtonType
        let isEnabled: Bool
        let action: () -> Void

        func makeUIView(context: Context) -> PKPaymentButton {
            let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: .automatic)
            // Matches WidgetUI.primaryButton, so the paid button sits in the
            // same rhythm as the rest of the sheet.
            button.cornerRadius = 10
            button.addTarget(context.coordinator, action: #selector(Coordinator.fire), for: .touchUpInside)
            return button
        }

        func updateUIView(_ button: PKPaymentButton, context: Context) {
            context.coordinator.action = action
            button.isEnabled = isEnabled
            button.alpha = isEnabled ? 1 : 0.5
        }

        func makeCoordinator() -> Coordinator { Coordinator(action: action) }

        final class Coordinator {
            var action: () -> Void
            init(action: @escaping () -> Void) { self.action = action }
            @objc func fire() { action() }
        }
    }
    #else
    // The package builds for macOS so FavWidgetsCore stays Mac-testable;
    // nothing pays there. Keeping a body here means call sites need no guard.
    public var body: some View {
        Button("Pay", action: action).disabled(!isEnabled)
    }
    #endif
}

#if os(iOS)
private extension WidgetApplePayButton.Purchase {
    var buttonType: PKPaymentButtonType {
        switch self {
        case .checkOut: return .checkout
        case .buy: return .buy
        case .subscribe: return .subscribe
        }
    }
}
#endif
