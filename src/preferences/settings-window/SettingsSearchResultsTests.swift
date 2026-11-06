import XCTest

final class SettingsSearchResultsTests: XCTestCase {
    let entries = [
        SettingsSearchEntry(label: "Theme", pageTitle: "Appearance", page: .section("appearance"), rowID: "appearanceTheme"),
        SettingsSearchEntry(label: "Open CmdTab at login", pageTitle: "General", page: .section("general"), rowID: "startAtLogin"),
        SettingsSearchEntry(label: "Theme", pageTitle: "Appearance", page: .section("appearance"), rowID: "appearanceTheme"),
    ]
    func testMatchesAndDeduplicates() {
        XCTAssertEqual(SettingsSearchResults.results("them", in: entries).map(\.rowID), ["appearanceTheme"])
        XCTAssertEqual(SettingsSearchResults.results("login", in: entries).map(\.page), [.section("general")])
    }
    func testNoMatchIsEmpty() { XCTAssertTrue(SettingsSearchResults.results("zzz", in: entries).isEmpty) }
}
