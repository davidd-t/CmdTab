import XCTest

final class ShortcutNamingTests: XCTestCase {
    private func s(_ apps: Int, _ spaces: Int, _ keys: String) -> ShortcutNamingInput { .init(appsIndex: apps, spacesIndex: spaces, keys: keys) }
    private func s(_ apps: Int, keys: String) -> ShortcutNamingInput { s(apps, 0, keys) }
    func testNamesComeFromWhichAppsAreShown() {
        XCTAssertEqual(ShortcutNaming.names([s(0, keys: "⌘⇥"), s(1, keys: "⌘`")]), ["All windows", "Windows of the current app"])
        XCTAssertEqual(ShortcutNaming.names([s(2, keys: "a"), s(3, keys: "b"), s(4, keys: "c")]),
                       ["Windows of other apps", "Windows under the pointer", "Windows of the app under the pointer"])
    }
    func testDuplicateNamesGetTheirKeys() {
        XCTAssertEqual(ShortcutNaming.names([s(0, keys: "⌘⇥"), s(0, keys: "⌥⇥"), s(1, keys: "⌘`")]),
                       ["All windows (⌘⇥)", "All windows (⌥⇥)", "Windows of the current app"])
    }
    func testSubtitles() {
        XCTAssertEqual(ShortcutNaming.subtitle(s(0, 0, "⌘⇥")), "Every app, every Space")
        XCTAssertEqual(ShortcutNaming.subtitle(s(1, 0, "⌘`")), "Only the app you're in")
        XCTAssertEqual(ShortcutNaming.subtitle(s(0, 1, "x")), "Every app, visible Spaces")
        XCTAssertEqual(ShortcutNaming.subtitle(s(0, 2, "x")), "Every app, other Spaces")
        XCTAssertEqual(ShortcutNaming.subtitle(s(2, 2, "x")), "Every app except the one you're in, other Spaces")
        XCTAssertEqual(ShortcutNaming.subtitle(s(3, 2, "x")), "Only windows under the pointer")
    }
}
