import XCTest
@testable import Shaw

final class UpdateCheckTests: XCTestCase {
    func testNewerReleasesAreSpotted() {
        XCTAssertTrue(Store.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(Store.isNewer("v0.10.0", than: "0.9.3"), "numbers, not text: 10 is more than 9")
        XCTAssertTrue(Store.isNewer("v1.0", than: "0.9.9"))
        XCTAssertFalse(Store.isNewer("v0.1.0", than: "0.1.0"))
        XCTAssertFalse(Store.isNewer("v0.1", than: "0.1.0"))
        XCTAssertFalse(Store.isNewer("v0.1.0", than: "0.2.0"))
    }
}
