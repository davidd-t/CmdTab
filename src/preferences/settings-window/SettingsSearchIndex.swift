import Cocoa

/// Search index for the Settings UI.
///
/// Registration is push, not pull: as each widget factory (`LabelAndControl.makeDropdown`,
/// `TableGroupView.makeText`, etc.) builds a control, it pushes the strings it would produce — plus
/// a `SettingsSearchHighlightTarget` (a closure-bag that knows how to highlight that specific
/// control) — into the currently-active `Builder`. `SettingsWindow.addSection` opens a builder
/// before calling the section's view-builder closure and closes it after. A post-construction walk
/// still runs as a safety net for any direct widget creation that bypasses the factories.
enum SettingsSearchIndex {

    // MARK: - Inline registration

    /// The currently-active builder, or nil outside of `indexed(_:)`. Factories check this and
    /// silently no-op when nil so they can be called from any context.
    static var current: Builder?

    final class Builder {
        var strings: [String] = []
        var targets: [SettingsSearchHighlightTarget] = []
        /// Labels that live on a detail page rather than on the section's own page, with where
        /// a search result for them goes (resolved when searching, since the page can change).
        var detailStrings: [(strings: [String], destination: () -> (page: SettingsPage, title: String))] = []
    }

    /// Run `build` with a fresh builder active, then return the built value alongside the
    /// accumulated index. Nested `indexed` calls restore the previous builder on exit.
    static func indexed<T>(_ build: () -> T) -> (result: T, builder: Builder) {
        let previous = current
        let builder = Builder()
        current = builder
        defer { current = previous }
        let result = build()
        return (result, builder)
    }

    /// Push a string. No-op if the string is empty/whitespace-only or no builder is active.
    static func registerString(_ s: String?) {
        guard let current, let s else { return }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { current.strings.append(trimmed) }
    }

    /// Push multiple strings — convenience for popups, segmented controls, info-button tooltips.
    static func registerStrings(_ strings: [String]) {
        guard let current else { return }
        for s in strings {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { current.strings.append(t) }
        }
    }

    /// Push labels shown on a detail page (e.g. a shortcut's own page). `destination` names the page
    /// a search result opens and its title.
    static func registerDetailStrings(_ strings: [String], destination: @escaping () -> (page: SettingsPage, title: String)) {
        guard let current else { return }
        let trimmed = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        current.detailStrings.append((trimmed, destination))
    }

    /// Push a highlight target. No-op if nil (factories may pass nil for non-highlightable cases).
    static func registerTarget(_ target: SettingsSearchHighlightTarget?) {
        guard let target, let current else { return }
        current.targets.append(target)
    }

    /// Run `build` with no builder active, so nothing it creates is registered. For content a
    /// section publishes itself (see `SettingsWindow.refreshSectionSearchContent`).
    static func unindexed<T>(_ build: () -> T) -> T {
        let previous = current
        current = nil
        defer { current = previous }
        return build()
    }
}
