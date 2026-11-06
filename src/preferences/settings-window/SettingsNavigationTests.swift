import XCTest

final class SettingsNavigationTests: XCTestCase {
    func testOpenPushesAndBackForwardWalkHistory() {
        var n = SettingsNavigation(start: .section("appearance"))
        n.open(.section("shortcuts")); n.open(.shortcut(1))
        XCTAssertEqual(n.current, .shortcut(1)); XCTAssertTrue(n.canGoBack); XCTAssertFalse(n.canGoForward)
        n.goBack(); XCTAssertEqual(n.current, .section("shortcuts")); XCTAssertTrue(n.canGoForward)
        n.goForward(); XCTAssertEqual(n.current, .shortcut(1))
    }
    func testOpeningTheCurrentPageAddsNothing() {
        var n = SettingsNavigation(start: .section("general"))
        n.open(.section("general")); XCTAssertFalse(n.canGoBack)
    }
    func testOpenAfterBackDropsForwardHistory() {
        var n = SettingsNavigation(start: .section("appearance"))
        n.open(.section("general")); n.goBack(); n.open(.section("exceptions"))
        XCTAssertFalse(n.canGoForward)
    }
    func testRemovingTheViewedShortcutFallsBackAndPrunesHistory() {
        var n = SettingsNavigation(start: .section("shortcuts"))
        n.open(.shortcut(2)); n.open(.section("general")); n.open(.shortcut(2))
        n.removePages(where: { $0 == .shortcut(2) }, fallback: .section("shortcuts"))
        XCTAssertEqual(n.current, .section("shortcuts"))
        n.goBack(); XCTAssertEqual(n.current, .section("general"))
        n.goBack(); XCTAssertNotEqual(n.current, .shortcut(2))
    }
    func testSearchReturnsToThePageBeforeIt() {
        var n = SettingsNavigation(start: .section("general"))
        n.beginSearch(); XCTAssertEqual(n.current, .search)
        n.beginSearch(); n.endSearch(); XCTAssertEqual(n.current, .section("general"))
        XCTAssertFalse(n.canGoBack)
    }
}
