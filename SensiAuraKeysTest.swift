import XCTest
@testable import SensiAuraKeys

final class SensiAuraKeysTests: XCTestCase {
    func testDefaultConfiguration() {
        let configuration = SensiAuraKeys.Configuration()
        XCTAssertEqual(configuration.applicationName, "Dylanbrandonsmith123's Application")
        XCTAssertEqual(configuration.ownerID, "MQqz402Fyv")
        XCTAssertEqual(configuration.version, "1.0")
    }
}