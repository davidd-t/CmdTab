import XCTest

final class ShortcutLookTests: XCTestCase {
    func testFollowsAppearanceUnlessAnyOverrideIsStored() {
        XCTAssertTrue(ShortcutLook.followsAppearance(stored: ["appearanceStyle": "1"], index: 1))
        XCTAssertFalse(ShortcutLook.followsAppearance(stored: ["appearanceThemeOverride2": "1"], index: 1))
        XCTAssertTrue(ShortcutLook.followsAppearance(stored: ["appearanceThemeOverride2": "1"], index: 0))
        XCTAssertFalse(ShortcutLook.followsAppearance(stored: ["previewFocusedWindowOverride": "true"], index: 0))
    }
    func testTurningOffWritesAllFiveFromTheEffectiveValues() {
        let globals = ["appearanceStyle": "2", "appearanceSize": "3", "appearanceTheme": "2", "shortcutStyle": "0", "previewFocusedWindow": "false"]
        XCTAssertEqual(ShortcutLook.writesWhenTurnedOff(index: 1, effective: { globals[$0]! }),
                       ["appearanceStyleOverride2": "2", "appearanceSizeOverride2": "3", "appearanceThemeOverride2": "2",
                        "shortcutStyleOverride2": "0", "previewFocusedWindowOverride2": "false"])
    }
    func testTurningOnRemovesAllFive() {
        XCTAssertEqual(Set(ShortcutLook.keysToRemoveWhenTurnedOn(index: 0)),
                       ["appearanceStyleOverride", "appearanceSizeOverride", "appearanceThemeOverride", "shortcutStyleOverride", "previewFocusedWindowOverride"])
    }
    func testKeyMatchesIndexToNameRule() {
        XCTAssertEqual(ShortcutLook.key("x", 0), "x")
        XCTAssertEqual(ShortcutLook.key("x", 2), "x3")
    }
}
