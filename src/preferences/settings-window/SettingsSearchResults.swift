import Foundation

/// One searchable setting: its label, the page it lives on, and the row to bring into view.
struct SettingsSearchEntry: Equatable {
    let label: String
    let pageTitle: String
    let page: SettingsPage
    let rowID: String
}

enum SettingsSearchResults {
    /// The entries whose label matches `query` (`SettingsSearch` rules), in entry order, without
    /// repeats of the same label on the same page, at most `limit` of them.
    static func results(_ query: String, in entries: [SettingsSearchEntry], limit: Int = 30) -> [SettingsSearchEntry] {
        guard !SettingsSearch.isQueryEmpty(query) else { return [] }
        var seen = Set<SettingsSearchResultKey>()
        var results = [SettingsSearchEntry]()
        for entry in entries where results.count < limit {
            guard SettingsSearch.match(query, in: entry.label) != nil,
                  seen.insert(SettingsSearchResultKey(label: entry.label, page: entry.page)).inserted else { continue }
            results.append(entry)
        }
        return results
    }
}

private struct SettingsSearchResultKey: Hashable {
    let label: String
    let page: SettingsPage
}
