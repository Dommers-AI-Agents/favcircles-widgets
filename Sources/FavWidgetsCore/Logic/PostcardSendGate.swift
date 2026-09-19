import Foundation

/// Whether the postcard composer's Send button is live, and if not, why.
///
/// This was an expression inside the view and it was wrong twice in one day:
/// once refusing to send with a reason that contradicted the screen ("Fill in
/// the mailing address" under a full form), and once *allowing* a send that
/// quietly dropped the printed card the person had asked for. Both are the
/// same failure — the button and the explanation disagreeing with each other —
/// so the rule and its reason now live together, in one place, under test.
public enum PostcardSendGate {

    /// Everything the button depends on. Named rather than positional because
    /// six booleans in a row is how the second bug got written.
    public struct Inputs {
        public let hasPhoto: Bool
        public let isSending: Bool
        public let hasInvalidEmail: Bool
        public let tooManyEmails: Bool
        /// Someone to send the digital card to: a chosen connection or a valid email.
        public let hasDigitalRecipient: Bool
        /// The printed-card switch is on AND the device/server can actually mail.
        public let mailRequested: Bool
        /// The address is complete, checked, and deliverable.
        public let mailReady: Bool

        public init(hasPhoto: Bool, isSending: Bool, hasInvalidEmail: Bool, tooManyEmails: Bool,
                    hasDigitalRecipient: Bool, mailRequested: Bool, mailReady: Bool) {
            self.hasPhoto = hasPhoto
            self.isSending = isSending
            self.hasInvalidEmail = hasInvalidEmail
            self.tooManyEmails = tooManyEmails
            self.hasDigitalRecipient = hasDigitalRecipient
            self.mailRequested = mailRequested
            self.mailReady = mailReady
        }
    }

    public static func canSend(_ input: Inputs) -> Bool {
        guard input.hasPhoto, !input.isSending, !input.hasInvalidEmail, !input.tooManyEmails else {
            return false
        }
        // Asking for a printed card and then sending without one is doing less
        // than you were told to. If the switch is on, the address decides.
        if input.mailRequested && !input.mailReady { return false }
        // Otherwise anything that reaches someone is enough: a connection, an
        // email, or the printed card on its own.
        return input.hasDigitalRecipient || (input.mailRequested && input.mailReady)
    }
}
