import Testing
@testable import FavWidgetsCore

/// The Send button and its explanation have to agree. Both bugs this rule was
/// extracted for were failures of that agreement.
@Suite("Postcard send gate")
struct PostcardSendGateTests {
    private func inputs(hasPhoto: Bool = true, isSending: Bool = false,
                        hasInvalidEmail: Bool = false, tooManyEmails: Bool = false,
                        hasDigitalRecipient: Bool = true,
                        mailRequested: Bool = false, mailReady: Bool = false)
    -> PostcardSendGate.Inputs {
        .init(hasPhoto: hasPhoto, isSending: isSending, hasInvalidEmail: hasInvalidEmail,
              tooManyEmails: tooManyEmails, hasDigitalRecipient: hasDigitalRecipient,
              mailRequested: mailRequested, mailReady: mailReady)
    }

    @Test func aPhotoAndSomeoneToSendItToIsEnough() {
        #expect(PostcardSendGate.canSend(inputs()))
    }

    @Test func noPhotoNeverSends() {
        #expect(!PostcardSendGate.canSend(inputs(hasPhoto: false)))
        // Not even with a perfectly good printed card waiting.
        #expect(!PostcardSendGate.canSend(inputs(hasPhoto: false, mailRequested: true, mailReady: true)))
    }

    @Test func nobodyToSendToNeverSends() {
        #expect(!PostcardSendGate.canSend(inputs(hasDigitalRecipient: false)))
    }

    /// The bug Wes hit: mail switch on, address blank, a connection chosen.
    /// Send used to light up and then post the digital card only, dropping the
    /// printed one without a word.
    @Test func askingToMailWithNoAddressBlocksTheSend() {
        #expect(!PostcardSendGate.canSend(inputs(hasDigitalRecipient: true,
                                                 mailRequested: true, mailReady: false)))
    }

    @Test func askingToMailWithAGoodAddressSends() {
        #expect(PostcardSendGate.canSend(inputs(hasDigitalRecipient: true,
                                                mailRequested: true, mailReady: true)))
    }

    /// A printed card on its own is a complete send — no connection, no email.
    @Test func aPrintedCardAloneIsEnough() {
        #expect(PostcardSendGate.canSend(inputs(hasDigitalRecipient: false,
                                                mailRequested: true, mailReady: true)))
    }

    /// The switch being off means the address is irrelevant, however empty.
    @Test func anUnrequestedPrintedCardNeverBlocksAnything() {
        #expect(PostcardSendGate.canSend(inputs(mailRequested: false, mailReady: false)))
    }

    @Test func badEmailsBlockEvenWithEverythingElseRight() {
        #expect(!PostcardSendGate.canSend(inputs(hasInvalidEmail: true)))
        #expect(!PostcardSendGate.canSend(inputs(tooManyEmails: true)))
        #expect(!PostcardSendGate.canSend(inputs(hasInvalidEmail: true,
                                                 mailRequested: true, mailReady: true)))
    }

    @Test func aSendAlreadyInFlightBlocksASecondTap() {
        #expect(!PostcardSendGate.canSend(inputs(isSending: true)))
    }
}
