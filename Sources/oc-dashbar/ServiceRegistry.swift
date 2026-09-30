import Foundation

/// One `service.json` written by `oc-dash server start`, decoded.
///
/// The file belongs to oc-dash. Every name in it and every name of the file
/// itself is fixed by the contract between the two repositories and is
/// spelled with a `Config` constant rather than a string literal here, so the
/// contract is a diff in one file instead of a search through both trees.
struct ServiceRegistryEntry: Equatable {
    /// The port the dashboard bound. Cross-checked against the URL, because a
    /// file where the two disagree is a file with a bug in it and one of the two
    /// values has to be wrong.
    let port: Int

    /// The process that wrote the file. Checked for liveness before the entry
    /// is believed; see `ServiceRegistry.isProcessAlive`.
    let pid: Int32

    /// The dashboard's base URL, `http://127.0.0.1:4021`, with no path. The
    /// widget path is appended by `Config.resolveWidgetURL` so the registry
    /// never has to know what the panel loads.
    let baseURL: URL

    /// Reported by the writer. Nothing in this shell compares it to anything,
    /// so it is decoded only to prove the file is the shape it claims to be.
    let version: String?
}

/// What a registry file turned out to be. Present but unusable is
/// `.rejected` with the reason, never a half-built entry: a base URL taken
/// from a file whose port could not be read is how a panel ends up pointing at
/// nothing while looking like it tried.
enum ServiceRegistryFile: Equatable {
    case entry(ServiceRegistryEntry)
    case rejected(String)
}

/// Everything this shell does to find a registry file. Read-only and
/// discover-only on purpose: it opens a file and asks the kernel whether a
/// process is alive. It never writes the file, never deletes it, and never
/// signals the process, because oc-dash owns all three.
enum ServiceRegistry {
    /// `$XDG_STATE_HOME/oc-dash/service.json`, falling back to
    /// `$HOME/.local/state/oc-dash/service.json`.
    ///
    /// Those two rules are not this shell's invention. `@opencode/client`
    /// resolves `opencode/service.json` the same way in
    /// `node_modules/@opencode/client/dist/promise/service.js`, in a function
    /// called `fallback()`, and oc-dash already reads the opencode registry
    /// through that client. A third convention would have been a third thing
    /// to teach.
    ///
    /// Pure, so a test can assert both paths and never touch the real state
    /// directory.
    static func registryPath(stateHome: String?, homeDirectory: String) -> String {
        let base =
            (stateHome?.isEmpty == false)
            ? URL(fileURLWithPath: stateHome!)
            : URL(fileURLWithPath: homeDirectory).appendingPathComponent(Config.homeStateDirectory)
        return
            base
            .appendingPathComponent(Config.registryDirectoryName)
            .appendingPathComponent(Config.registryFileName)
            .path
    }

    /// The file this process would read. Only for the log: the line that says
    /// which source won also names the file that was consulted, so an ignored
    /// or unreadable registry leaves a trace.
    static func currentPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        registryPath(
            stateHome: environment[Config.stateHomeEnvironmentKey],
            homeDirectory: environment["HOME"] ?? NSHomeDirectory()
        )
    }

    /// The file's text, or nil when there is no file.
    ///
    /// A file that exists and cannot be read returns nil too, and is treated
    /// as no file. That is a deliberate limit rather than an oversight: this is
    /// a 90-byte file in the user's own state directory, the failure mode is a
    /// permissions change nobody made on purpose, and the log still prints the
    /// path it looked at. Spinning on an unreadable file to produce a second
    /// wording for "could not read it" buys nothing.
    static func currentText(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        try? String(contentsOfFile: currentPath(environment: environment), encoding: .utf8)
    }

    /// Decodes one registry file. Total: every input produces either an entry
    /// or a reason, and no input produces an entry that is partly made up.
    static func decode(_ text: String) -> ServiceRegistryFile {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(text.utf8))
        }
        catch let error as DecodingError {
            return .rejected(reason(for: error))
        }
        catch {
            return .rejected("unreadable")
        }

        // A pid of 0 is not a process and `kill(0, 0)` signals the caller's
        // own process group, which would make a junk file look like a live
        // dashboard. Anything above Int32 is not a pid this API can signal.
        guard payload.pid > 0, payload.pid <= Int(Int32.max) else {
            return .rejected("\"pid\" is \(payload.pid), not a process id")
        }
        guard let base = URL(string: payload.url), isHTTP(base) else {
            return .rejected("\"url\" (\(payload.url)) is not an http or https URL")
        }
        guard let urlPort = base.port else {
            return .rejected("\"url\" (\(payload.url)) names no port")
        }
        // The writer composes the URL from the port, so the two cannot
        // disagree unless something else wrote the file. When they do, refusing
        // the file is the only answer that cannot be wrong: picking either
        // value guesses.
        guard urlPort == payload.port else {
            return .rejected("\"port\" (\(payload.port)) and \"url\" (\(payload.url)) disagree")
        }
        return .entry(
            ServiceRegistryEntry(
                port: payload.port,
                pid: Int32(payload.pid),
                baseURL: base,
                version: payload.version
            )
        )
    }

    /// Whether a pid names a process that is running right now.
    ///
    /// `kill(pid, 0)` is the check, and `EPERM` counts as alive: the process
    /// exists, this shell just may not signal it. Only `ESRCH` is a real "no".
    ///
    /// What this cannot see is a recycled pid, which is a false "yes" for a
    /// stale file. The cost of being wrong is bounded and small, the webview
    /// loads a port nobody is serving and the panel shows the offline page,
    /// which is a visible failure rather than a silent one. Confirming the
    /// process name as well would close it, and is the one addition worth
    /// making if this ever misbehaves in the field.
    static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Exactly the four keys in the contract, and nothing optional except the
    /// version.
    ///
    /// Decoded rather than cast, on purpose. `JSONSerialization` hands back an
    /// `NSNumber` for `true`, so `{"pid": true}` cast to a number is pid 1, and
    /// a file written by something that is not oc-dash would be believed.
    /// `JSONDecoder` refuses it.
    private struct Payload: Decodable {
        let port: Int
        let pid: Int
        let url: String
        let version: String?
    }

    private static func isHTTP(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    /// A short reason, because the whole point of reporting a rejected file is
    /// that a person reads the line and knows which key to look at.
    private static func reason(for error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "no \"\(key.stringValue)\""
        case .typeMismatch(let type, let context):
            return "\"\(field(context))\" is not a \(type)"
        case .valueNotFound(let type, let context):
            return "\"\(field(context))\" is null, not a \(type)"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? "not JSON"
                : "\"\(field(context))\" is not valid JSON"
        @unknown default:
            return "unreadable"
        }
    }

    private static func field(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "the file" : path
    }
}
