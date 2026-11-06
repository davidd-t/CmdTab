import Foundation

/// Maps between a stored "true"/"false" preference and a switch position.
/// `reversed` is for "Hide …" preferences, whose switch reads "Show …".
enum SwitchValue {
    static func isOn(stored: String, reversed: Bool) -> Bool {
        (stored == "true") != reversed
    }

    static func stored(isOn: Bool, reversed: Bool) -> String {
        (isOn != reversed) ? "true" : "false"
    }
}
