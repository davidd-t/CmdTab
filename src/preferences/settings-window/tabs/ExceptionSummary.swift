import Foundation

/// The gray line under an exception in the Exceptions list: what applies to that app.
enum ExceptionSummary {
    static func text(hide: ExceptionHidePreference, ignore: ExceptionIgnorePreference) -> String {
        var parts = [String]()
        switch hide {
        case .none: break
        case .always: parts.append(NSLocalizedString("Always hidden", comment: ""))
        case .whenNoOpenWindow: parts.append(NSLocalizedString("Hidden when it has no open window", comment: ""))
        case .windowTitleContains: parts.append(NSLocalizedString("Some windows hidden by title", comment: ""))
        }
        switch ignore {
        case .none: break
        case .always: parts.append(NSLocalizedString("CmdTab's shortcuts always off", comment: ""))
        case .whenFullscreen: parts.append(NSLocalizedString("CmdTab's shortcuts off when fullscreen", comment: ""))
        }
        return parts.isEmpty ? NSLocalizedString("No rules yet", comment: "An exception that changes nothing") : parts.joined(separator: " · ")
    }
}
