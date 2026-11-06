import Foundation

/// A page the Settings window can show. `shortcut(9)` is the trackpad gesture.
enum SettingsPage: Hashable {
    case section(String)
    case shortcut(Int)
    case exception(Int)
    case search
}

/// Back/forward history for the Settings window. Search is not a history entry: it remembers
/// the page it replaced and restores it when it ends.
struct SettingsNavigation {
    private(set) var current: SettingsPage
    private var backStack = [SettingsPage]()
    private var forwardStack = [SettingsPage]()
    private var pageBeforeSearch: SettingsPage?

    init(start: SettingsPage) {
        current = start
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    mutating func open(_ page: SettingsPage) {
        endSearch()
        guard page != current else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = page
    }

    mutating func goBack() {
        endSearch()
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        current = previous
    }

    mutating func goForward() {
        endSearch()
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        current = next
    }

    mutating func removePages(where shouldRemove: (SettingsPage) -> Bool, fallback: SettingsPage) {
        if let before = pageBeforeSearch, shouldRemove(before) { pageBeforeSearch = fallback }
        if shouldRemove(current) && current != .search { current = fallback }
        backStack = Self.collapse(backStack.filter { !shouldRemove($0) })
        // forwardStack is stored with the nearest page last
        forwardStack = Array(Self.collapse(forwardStack.reversed().filter { !shouldRemove($0) }).reversed())
        let reference = pageBeforeSearch ?? current
        while backStack.last == reference { backStack.removeLast() }
        while forwardStack.last == reference { forwardStack.removeLast() }
    }

    mutating func beginSearch() {
        guard pageBeforeSearch == nil else { return }
        pageBeforeSearch = current
        current = .search
    }

    mutating func endSearch() {
        guard let page = pageBeforeSearch else { return }
        pageBeforeSearch = nil
        current = page
    }

    private static func collapse(_ pages: [SettingsPage]) -> [SettingsPage] {
        var result = [SettingsPage]()
        for page in pages where page != result.last { result.append(page) }
        return result
    }
}
