class CliEvents {
    private static var listening = false
    static let portName = "\(App.bundleIdentifier).cli"

    static func observe() {
        guard !listening else { return }
        listening = true
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        if let messagePort = CFMessagePortCreateLocal(nil, portName as CFString, handleEvent, &context, nil),
           let source = CFMessagePortCreateRunLoopSource(nil, messagePort, 0) {
            CFRunLoopAddSource(BackgroundWork.cliEventsThread.runLoop, source, .commonModes)
        } else {
            Logger.error { "Can't listen on message port. Is another CmdTab already running?" }
            // TODO: should we quit or restart here?
            // It's complex since CmdTab can be restarted sometimes,
            // and the new instance may coexist with the old for some duration
            // There is also the case of multiple instances at login
        }
    }

    /// Returning nil is not an error the caller can see: a NULL from a message-port callback arrives as a
    /// zero-byte reply, so the CLI prints an empty line and exits 0, exactly like a healthy call. Every
    /// way out therefore says in the log what it could not do.
    private static let handleEvent: CFMessagePortCallBack = { (_: CFMessagePort?, _: Int32, _ data: CFData?, _: UnsafeMutableRawPointer?) in
        Logger.debug { "" }
        guard let data, let message = String(data: data as Data, encoding: .utf8) else {
            Logger.error { "Failed to decode message" }
            return nil
        }
        Logger.info { message }
        let output = CliServer.executeCommandAndSendReponse(message)
        do {
            let reply = try CliServer.jsonEncoder.encode(output)
            Logger.debug { "replying \(reply.count) bytes to \(message): \(String(data: reply.prefix(60), encoding: .utf8) ?? "?")" }
            return Unmanaged.passRetained(reply as CFData)
        } catch {
            Logger.error { "Failed to encode the response to \(message): \(error)" }
            return nil
        }
    }
}

class CliServer {
    /// `JSONEncoder` refuses a NaN or an infinite `Double` by default. Window geometry comes from AX and
    /// can be either, and one such window would otherwise make every response fail to encode for as long
    /// as it exists — silently, since the client cannot tell a failed reply from an empty one.
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }()
    static let error = "error"
    static let noOutput = "noOutput"

    // main.sync is safe here: the main thread never synchronously waits on the CLI thread
    static func executeCommandAndSendReponse(_ rawValue: String) -> Codable {
        var output: Codable = ""
        DispatchQueue.main.sync {
            output = executeCommandAndSendReponse_(rawValue)
        }
        return output
    }

    private static func executeCommandAndSendReponse_(_ rawValue: String) -> Codable {
        if rawValue == "--list" {
            return JsonWindowList(windows: Windows.list
                .filter { !$0.isWindowlessApp }
                .map { JsonWindow(id: $0.cgWindowId, title: $0.title) }
            )
        }
        if rawValue == "--detailed-list" {
            return JsonWindowFullList(windows: Windows.list
                .filter { !$0.isWindowlessApp }
                .map {
                    JsonWindowFull(
                        id: $0.cgWindowId,
                        title: $0.title,
                        appName: $0.application.localizedName,
                        appBundleId: $0.application.bundleIdentifier,
                        spaceIndexes: $0.spaceIndexes,
                        lastFocusOrder: $0.lastFocusOrder,
                        creationOrder: $0.creationOrder,
                        isTabbed: $0.isTabbed,
                        isHidden: $0.isHidden,
                        isFullscreen: $0.isFullscreen,
                        isMinimized: $0.isMinimized,
                        isOnAllSpaces: $0.isOnAllSpaces,
                        position: $0.position,
                        size: $0.size
                    )
                }
            )
        }
        if rawValue.hasPrefix("--focus="),
           let id = CGWindowID(rawValue.dropFirst("--focus=".count)), let window = (Windows.list.first { $0.cgWindowId == id }) {
            window.focus()
            return noOutput
        }
        if rawValue.hasPrefix("--focusUsingLastFocusOrder="),
           let lastFocusOrder = Int(rawValue.dropFirst("--focusUsingLastFocusOrder=".count)), let window = (Windows.list.first { $0.lastFocusOrder == lastFocusOrder }) {
            window.focus()
            return noOutput
        }
        if rawValue.hasPrefix("--show="),
           let shortcutIndex = Int(rawValue.dropFirst("--show=".count)), (0..<Preferences.shortcutCount).contains(shortcutIndex) {
            App.showUi(shortcutIndex)
            return noOutput
        }
        // The counterpart to `--show=`. `--show=` opens the switcher without making CmdTab the active app,
        // and in that state a synthetic Esc only arrives through the global cghid tap, so scripts close it here.
        if rawValue == "--hide" {
            App.hideUi()
            return noOutput
        }
        return error
    }


    private struct JsonWindowList: Codable {
        var windows: [JsonWindow]
    }

    private struct JsonWindow: Codable {
        var id: CGWindowID?
        var title: String
    }

    private struct JsonWindowFullList: Codable {
        var windows: [JsonWindowFull]
    }

    private struct JsonWindowFull: Codable {
        var id: CGWindowID?
        var title: String
        // -- additional properties
        var appName: String?
        var appBundleId: String?
        var spaceIndexes: [SpaceIndex]
        var lastFocusOrder: Int
        var creationOrder: Int
        var isTabbed: Bool
        var isHidden: Bool
        var isFullscreen: Bool
        var isMinimized: Bool
        var isOnAllSpaces: Bool
        var position: CGPoint?
        var size: CGSize?
    }
}

class CliClient {
    static func detectCommand() -> String? {
        let args = CommandLine.arguments
        if args.count == 2 && !args[1].starts(with: "--logs=") {
            if args[1] == "--list" || args[1] == "--detailed-list" || args[1] == "--hide" || args[1].hasPrefix("--focus=") || args[1].hasPrefix("--focusUsingLastFocusOrder=") || args[1].hasPrefix("--show=") {
                return args[1]
            }
        }
        return nil
    }

    /// Every failure exits non-zero and says which one it was, on stderr so it cannot be mistaken for the
    /// answer. Silence on stdout with exit 0 means one thing only: the command ran and has no output.
    /// A reply of zero bytes is a failure, not an answer — that is what the callback returning NULL looks
    /// like from here, and reading it as success is what let a broken port pass for a healthy one.
    static func sendCommandAndProcessResponse(_ command: String) {
        do {
            let serverPortClient = try CFMessagePortCreateRemote(nil, CliEvents.portName as CFString).unwrapOrThrow()
            let data = try command.data(using: .utf8).unwrapOrThrow()
            var returnData: Unmanaged<CFData>?
            let status = CFMessagePortSendRequest(serverPortClient, 0, data as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &returnData)
            guard let responseData = returnData?.takeRetainedValue() as Data?, !responseData.isEmpty else {
                fail("CmdTab did not answer \(command) (CFMessagePortSendRequest status \(status), "
                    + "\(returnData == nil ? "no reply" : "empty reply"))")
            }
            guard let response = String(data: responseData, encoding: .utf8) else {
                fail("CmdTab's answer to \(command) is \(responseData.count) bytes that are not text")
            }
            guard response != "\"\(CliServer.error)\"" else {
                fail("Couldn't execute command. Is it correct?")
            }
            if response != "\"\(CliServer.noOutput)\"" {
                print(response)
            }
            exit(0)
        } catch {
            fail("CmdTab.app needs to be running for CLI commands to work")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
