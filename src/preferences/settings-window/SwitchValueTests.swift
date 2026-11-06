import XCTest

final class SwitchValueTests: XCTestCase {
    func testReversedHidePreferenceKeepsItsMeaning() {
        XCTAssertFalse(SwitchValue.isOn(stored: "true", reversed: true))
        XCTAssertTrue(SwitchValue.isOn(stored: "false", reversed: true))
        XCTAssertEqual(SwitchValue.stored(isOn: true, reversed: true), "false")
        XCTAssertEqual(SwitchValue.stored(isOn: false, reversed: true), "true")
    }
    func testPlainSwitch() {
        XCTAssertTrue(SwitchValue.isOn(stored: "true", reversed: false))
        XCTAssertEqual(SwitchValue.stored(isOn: false, reversed: false), "false")
    }
}
