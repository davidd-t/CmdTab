import XCTest

final class ExceptionSummaryTests: XCTestCase {
    func testSummaries() {
        XCTAssertEqual(ExceptionSummary.text(hide: .whenNoOpenWindow, ignore: .none), "Hidden when it has no open window")
        XCTAssertEqual(ExceptionSummary.text(hide: .none, ignore: .whenFullscreen), "CmdTab's shortcuts off when fullscreen")
        XCTAssertEqual(ExceptionSummary.text(hide: .always, ignore: .always), "Always hidden · CmdTab's shortcuts always off")
        XCTAssertEqual(ExceptionSummary.text(hide: .windowTitleContains, ignore: .none), "Some windows hidden by title")
        XCTAssertEqual(ExceptionSummary.text(hide: .none, ignore: .none), "No rules yet")
    }
}
