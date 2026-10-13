import XCTest
@testable import FavWidgetsCore

final class RunFollowersCopyTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(RunFollowersCopy.names(["Brittany"]), "Brittany")
        XCTAssertEqual(RunFollowersCopy.names(["Brittany", "Amanda"]), "Brittany and Amanda")
        XCTAssertEqual(RunFollowersCopy.names(["Brittany", "Amanda", "Joseph"]), "Brittany, Amanda and Joseph")
        XCTAssertEqual(RunFollowersCopy.names(["A", "B", "C", "D"]), "A, B and 2 others")
    }

    func testStatus() {
        let three = ["Brittany", "Amanda", "Joseph"]
        XCTAssertEqual(RunFollowersCopy.status(waiting: three, told: [], noSignal: false), "📣 Telling Brittany, Amanda and Joseph…")
        XCTAssertEqual(RunFollowersCopy.status(waiting: three, told: [], noSignal: true), "📵 No signal · we'll tell Brittany, Amanda and Joseph when you're back")
        XCTAssertEqual(RunFollowersCopy.status(waiting: [], told: three, noSignal: false), "👀 Brittany, Amanda and Joseph know you're running")
        XCTAssertEqual(RunFollowersCopy.status(waiting: [], told: ["Brittany"], noSignal: false), "👀 Brittany knows you're running")
        XCTAssertNil(RunFollowersCopy.status(waiting: [], told: [], noSignal: false))
    }
}
