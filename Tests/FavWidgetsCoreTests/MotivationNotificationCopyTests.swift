import Testing
@testable import FavWidgetsCore

struct MotivationNotificationCopyTests {
    @Test func theStreakIsOnTheLine() {
        #expect(MotivationNotificationCopy.subtitle(streak: 0) == "Day 1 starts now. Move.")
        #expect(MotivationNotificationCopy.subtitle(streak: 1) == "🔥 1 day down. Don't you stop now.")
        #expect(MotivationNotificationCopy.subtitle(streak: 6) == "🔥 6-day streak on the line")
    }
}
