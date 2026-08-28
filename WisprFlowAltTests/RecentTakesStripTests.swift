import XCTest
@testable import WisprFlowAlt

final class RecentTakesStripTests: XCTestCase {
    func testNewestFiveKeepsFiveIdsNewestFirst() {
        let newestFirst = ["f", "e", "d", "c", "b", "a"]
        XCTAssertEqual(RecentTakes.newestFive(newestFirst), ["f", "e", "d", "c", "b"])
    }

    func testNewestFiveOnShortListReturnsAll() {
        XCTAssertEqual(RecentTakes.newestFive(["only"]), ["only"])
        XCTAssertEqual(RecentTakes.newestFive([String]()), [])
    }
}
