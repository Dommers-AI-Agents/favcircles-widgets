import Foundation
import Testing
import FavWidgetsCore
@testable import FavWidgets

/// Can I Pet Dat Dog (2026-10-22): share cards say what was shared and link
/// straight to it, never to private records; a non-member gets the generic card.
@MainActor
struct DogsWidgetTests {
    @Test func postShareCardLinksToThePost() {
        let post = DogPost(id: "p1", caption: "Zoomies at Freedom Park", dogs: [DogRef(id: "d", name: "Biscuit")], petCount: 23,
                           shareUrl: "https://api.favcircles.com/app/widget/dogs?post=p1")
        let card = DogsWidget.shareCardContent(post, image: nil)
        #expect(card.headline == "🐶 Biscuit")
        #expect(card.detail == "Zoomies at Freedom Park")
        #expect(card.stats.first?.value == "23" && card.stats.first?.label == "pets")
        #expect(card.linkTitle == "🐾 Can I pet Biscuit?")
        #expect(card.url?.absoluteString == "https://api.favcircles.com/app/widget/dogs?post=p1")
    }

    @Test func dailyAndDogCards() {
        let daily = DailyDog(id: "2026-10-22", date: "2026-10-22", kind: .joke, text: "Why did the dog sit in the shade? He didn't want to be a hot dog.")
        let d = DogsWidget.shareCardContent(daily, image: nil)
        #expect(d.headline == "😂 Dog joke" && d.url?.absoluteString == "https://api.favcircles.com/app/widget/dogs?daily=2026-10-22")
        let dog = DogProfile(id: "d", name: "Pepper", breed: "Lab mix", personality: "Professional sock thief")
        let p = DogsWidget.shareCardContent(dog, image: nil)
        #expect(p.headline == "🐶 Meet Pepper" && p.detail == "Lab mix\nProfessional sock thief" && p.url == nil)
    }

    @Test func notAMemberMeansTheGenericCard() async {
        let widget = FavWidgetRegistry.widget(id: "dogs")!
        let model = WidgetsTabModel(host: MockWidgetHost(), theme: .default)
        #expect(await widget.shareCard(context: model.context(for: widget.descriptor)) == nil)
    }

    @Test func launchFieldsStartEmpty() {
        let widget = FavWidgetRegistry.widget(id: "dogs")!
        let context = WidgetsTabModel(host: MockWidgetHost(), theme: .default).context(for: widget.descriptor)
        #expect(context.launchDogPostId == nil && context.launchDailyDogId == nil)
        context.launchDogPostId = "p1"
        #expect(context.launchDogPostId == "p1")
    }
}
