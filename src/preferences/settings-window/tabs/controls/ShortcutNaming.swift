import Foundation

struct ShortcutNamingInput {
    let appsIndex: Int
    let spacesIndex: Int
    let keys: String
}

enum ShortcutNaming {
    static let gestureName = "Trackpad swipe"

    private static let appsNames = [
        "All windows",
        "Windows of the current app",
        "Windows of other apps",
        "Windows under the pointer",
        "Windows of the app under the pointer",
    ]
    private static let appsPhrases = [
        "Every app",
        "Only the app you're in",
        "Every app except the one you're in",
        "Only windows under the pointer",
        "Only the app under the pointer",
    ]
    private static let spacesPhrases = [", every Space", ", visible Spaces", ", other Spaces"]

    static func names(_ shortcuts: [ShortcutNamingInput]) -> [String] {
        let base = shortcuts.map { appsNames[safe: $0.appsIndex] ?? appsNames[0] }
        return zip(base, shortcuts).map { name, s in
            base.filter { $0 == name }.count > 1 ? "\(name) (\(s.keys))" : name
        }
    }

    static func subtitle(_ s: ShortcutNamingInput) -> String {
        let apps = appsPhrases[safe: s.appsIndex] ?? appsPhrases[0]
        guard s.appsIndex == 0 || s.appsIndex == 2 else { return apps }
        return apps + (spacesPhrases[safe: s.spacesIndex] ?? spacesPhrases[0])
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
