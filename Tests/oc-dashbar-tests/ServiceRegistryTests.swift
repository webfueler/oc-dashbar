import Foundation
import Testing

@testable import oc_dashbar

/// The discovery contract between this shell and `oc-dash server start`.
///
/// Two of these tests are cross-repo contracts in the same sense as the quit
/// scheme in `ConfigTests`: the file path and the four JSON keys are written by
/// one repository and read by the other, so if either side moves, the mismatch
/// shows up here rather than as an empty panel at 2am.
@Suite("Service registry")
struct ServiceRegistryTests {
    /// A file exactly as the oc-dash side writes it.
    private func registry(port: Int = 4021, pid: Int32 = 4242, version: String = "0.1.8") -> String {
        """
        { "port": \(port), "pid": \(pid), "url": "http://127.0.0.1:\(port)", "version": "\(version)" }
        """
    }

    private func alive(_: Int32) -> Bool { true }
    private func dead(_: Int32) -> Bool { false }

    // MARK: - The file contract

    @Test("XDG_STATE_HOME wins, and an unset one falls back to $HOME/.local/state")
    func registryPath() {
        #expect(
            ServiceRegistry.registryPath(stateHome: "/tmp/state", homeDirectory: "/Users/someone")
                == "/tmp/state/oc-dash/service.json"
        )
        #expect(
            ServiceRegistry.registryPath(stateHome: nil, homeDirectory: "/Users/someone")
                == "/Users/someone/.local/state/oc-dash/service.json"
        )
        // Set-but-empty is the case a shell leaves behind with `XDG_STATE_HOME=`.
        // @opencode/client uses `??`, so an empty string would win there and
        // produce a relative path. Treating it as unset is the one place this
        // shell diverges, and it diverges toward not breaking.
        #expect(
            ServiceRegistry.registryPath(stateHome: "", homeDirectory: "/Users/someone")
                == "/Users/someone/.local/state/oc-dash/service.json"
        )
        // The names are literal here on purpose, the same reason the quit URL
        // test spells its string out. Config can always be edited to agree with
        // itself; this is the path oc-dash has to write.
        #expect(Config.registryDirectoryName == "oc-dash")
        #expect(Config.registryFileName == "service.json")
        #expect(Config.stateHomeEnvironmentKey == "XDG_STATE_HOME")
    }

    @Test("a file oc-dash wrote decodes to its port, pid and base URL")
    func decodesARealFile() {
        let decoded = ServiceRegistry.decode(registry(port: 4022, pid: 5150, version: "0.1.8"))
        #expect(
            decoded
                == .entry(
                    ServiceRegistryEntry(
                        port: 4022,
                        pid: 5150,
                        baseURL: URL(string: "http://127.0.0.1:4022")!,
                        version: "0.1.8"
                    )
                )
        )
    }

    @Test("version is optional, because a file without it still names a live server")
    func versionIsOptional() {
        guard
            case .entry(let entry) = ServiceRegistry.decode(
                #"{ "port": 4021, "pid": 7, "url": "http://127.0.0.1:4021" }"#
            )
        else {
            Issue.record("a file with port, pid and url must decode")
            return
        }
        #expect(entry.port == 4021)
        #expect(entry.pid == 7)
        #expect(entry.version == nil)
    }

    /// Every one of these is refused whole. The point is not the wording, it is
    /// that none of them yields an entry: a base URL taken from a file whose
    /// port could not be read is how a panel points at nothing while looking
    /// like it tried.
    @Test("a malformed file is rejected, never half-parsed")
    func rejectsMalformed() {
        let bad = [
            "not json at all",
            "",
            "{",
            "[]",
            #"{ "port": 4021, "pid": 7 }"#,  // no url
            #"{ "pid": 7, "url": "http://127.0.0.1:4021" }"#,  // no port
            #"{ "port": 4021, "url": "http://127.0.0.1:4021" }"#,  // no pid
            #"{ "port": 4021, "pid": true, "url": "http://127.0.0.1:4021" }"#,  // a bool is not a pid
            #"{ "port": 4021, "pid": 0, "url": "http://127.0.0.1:4021" }"#,  // 0 is the process group
            #"{ "port": 4021, "pid": -3, "url": "http://127.0.0.1:4021" }"#,
            #"{ "port": 4021, "pid": 99999999999999, "url": "http://127.0.0.1:4021" }"#,  // past Int32
            #"{ "port": 4021, "pid": 7, "url": "http://127.0.0.1:4022" }"#,  // port and url disagree
            #"{ "port": 4021, "pid": 7, "url": "127.0.0.1:4021" }"#,  // no scheme
            #"{ "port": 4021, "pid": 7, "url": "ftp://127.0.0.1:4021" }"#,
            #"{ "port": 4021, "pid": 7, "url": "http://127.0.0.1" }"#,  // no port in the url
            #"{ "port": 4021, "pid": 7, "url": "" }"#,
            #"{ "port": 4021, "pid": 7, "url": "http://127.0.0.1:4021", "version": 8 }"#,  // version is a string
        ]
        for text in bad {
            guard case .rejected = ServiceRegistry.decode(text) else {
                Issue.record("expected a rejection for: \(text)")
                continue
            }
        }
    }

    @Test("a rejection carries a reason that names the key, so the log line is actionable")
    func rejectionNamesTheKey() {
        guard case .rejected(let reason) = ServiceRegistry.decode(#"{ "port": 4021, "pid": 7 }"#) else {
            Issue.record("expected a rejection")
            return
        }
        #expect(reason.contains("url"))
        guard
            case .rejected(let disagreeing) = ServiceRegistry.decode(
                #"{ "port": 4021, "pid": 7, "url": "http://127.0.0.1:4022" }"#
            )
        else {
            Issue.record("expected a rejection")
            return
        }
        #expect(disagreeing.contains("disagree"))
    }

    // MARK: - Precedence

    @Test("level 1, the override, beats a live registry below it")
    func overrideBeatsRegistry() {
        let environment = [Config.urlEnvironmentKey: "http://127.0.0.1:4999/widget"]
        let resolved = Config.resolveWidgetURL(
            environment: environment,
            registryText: registry(port: 4022, pid: 5150),
            isProcessAlive: alive
        )
        #expect(resolved.url?.absoluteString == "http://127.0.0.1:4999/widget")
        #expect(resolved.source == .environmentOverride)
        // The override means the registry is not read at all, so there is no
        // outcome to report and the line says so.
        #expect(resolved.registry == nil)
    }

    @Test("level 2, a live registry, beats the built-in default below it")
    func registryBeatsDefault() {
        let resolved = Config.resolveWidgetURL(
            environment: [:],
            registryText: registry(port: 4022, pid: 5150),
            isProcessAlive: alive
        )
        #expect(resolved.url?.absoluteString == "http://127.0.0.1:4022/widget")
        #expect(resolved.source == .registry)
        #expect(resolved.registry == .won(port: 4022, pid: 5150))
    }

    @Test("level 3, the built-in default, is where everything else lands")
    func defaultIsLast() {
        let resolved = Config.resolveWidgetURL(environment: [:], registryText: nil, isProcessAlive: alive)
        #expect(resolved.url?.absoluteString == Config.defaultWidgetURLString)
        #expect(resolved.source == .builtInDefault)
        #expect(resolved.registry == .absent)
    }

    @Test("a dead pid does not win, and the outcome says which pid")
    func deadPidDoesNotWin() {
        let resolved = Config.resolveWidgetURL(
            environment: [:],
            registryText: registry(port: 4022, pid: 5150),
            isProcessAlive: dead
        )
        #expect(resolved.url?.absoluteString == Config.defaultWidgetURLString)
        #expect(resolved.source == .builtInDefault)
        #expect(resolved.registry == .deadProcess(pid: 5150))
    }

    @Test("a dead pid does not beat the override either")
    func deadPidDoesNotDisplaceTheOverride() {
        let resolved = Config.resolveWidgetURL(
            environment: [Config.urlEnvironmentKey: "http://127.0.0.1:4999/widget"],
            registryText: registry(pid: 5150),
            isProcessAlive: dead
        )
        #expect(resolved.url?.absoluteString == "http://127.0.0.1:4999/widget")
        #expect(resolved.source == .environmentOverride)
    }

    @Test("a missing file falls through cleanly instead of reporting a problem")
    func missingFileFallsThrough() {
        let resolved = Config.resolveWidgetURL(environment: [:], registryText: nil, isProcessAlive: alive)
        #expect(resolved.url?.absoluteString == "http://127.0.0.1:4021/widget")
        // Absent, not rejected: no file is the normal state for anyone who has
        // not run `oc-dash server start`, and the log line must not read like a
        // complaint about a file that was never there.
        #expect(resolved.registry == .absent)
    }

    @Test("an unreadable file falls through to the default and reports the reason")
    func malformedFallsThrough() {
        let resolved = Config.resolveWidgetURL(
            environment: [:],
            registryText: "half a file",
            isProcessAlive: alive
        )
        #expect(resolved.url?.absoluteString == Config.defaultWidgetURLString)
        #expect(resolved.source == .builtInDefault)
        guard case .rejected = resolved.registry else {
            Issue.record(
                "expected the registry to be reported as rejected, got \(String(describing: resolved.registry))"
            )
            return
        }
    }

    @Test("a set-but-blank override resolves to nothing rather than to the default")
    func unusableOverrideDoesNotFallThrough() {
        for raw in ["", "   ", "\n\t "] {
            let resolved = Config.resolveWidgetURL(
                environment: [Config.urlEnvironmentKey: raw],
                registryText: registry(port: 4022, pid: 5150),
                isProcessAlive: alive
            )
            #expect(resolved.url == nil)
            #expect(resolved.source == .unusable)
            // A typo must not turn into a panel that looks like it worked, which
            // is what silently dropping to the default would do.
            #expect(resolved.registry == nil)
        }
    }

    /// Locked in as it behaves, not as it should behave.
    ///
    /// `URL(string:)` accepts a relative string and percent-encodes its spaces,
    /// so `OC_DASHBAR_URL=not a url at all` resolves to a schemeless URL and the
    /// webview gets a navigation it cannot complete. Tightening the override
    /// parser is a different change, and it would need its own decision about
    /// whether a schemeless override is ever legitimate.
    @Test("a nonsense override still parses as a relative URL")
    func nonsenseOverrideIsStillAccepted() {
        let resolved = Config.resolveWidgetURL(
            environment: [Config.urlEnvironmentKey: "not a url at all"],
            registryText: registry(port: 4022, pid: 5150),
            isProcessAlive: alive
        )
        #expect(resolved.source == .environmentOverride)
        #expect(resolved.url?.absoluteString == "not%20a%20url%20at%20all")
    }

    @Test("the convenience signature still resolves with no registry text, so no registry")
    func oldSignatureIsUnchanged() {
        #expect(Config.resolvedWidgetURL(environment: [:])?.absoluteString == "http://127.0.0.1:4021/widget")
        let overridden = Config.resolvedWidgetURL(environment: [
            Config.urlEnvironmentKey: "http://127.0.0.1:4022/widget"
        ])
        #expect(overridden?.absoluteString == "http://127.0.0.1:4022/widget")
        #expect(Config.resolvedWidgetURL(environment: [Config.urlEnvironmentKey: "  "]) == nil)
    }

    // MARK: - Widget path

    @Test("the widget path is appended to whatever base the registry names")
    func widgetPathIsAppended() {
        for base in ["http://127.0.0.1:4022", "http://127.0.0.1:4022/", "http://localhost:4022/some/path?q=1#f"] {
            let text = #"{ "port": 4022, "pid": 5150, "url": "\#(base)" }"#
            let resolved = Config.resolveWidgetURL(environment: [:], registryText: text, isProcessAlive: alive)
            #expect(resolved.url?.absoluteString == "http://\(URL(string: base)!.host!):4022/widget", "base \(base)")
        }
    }

    @Test("https is accepted, because oc-dash may be put behind a tunnel on the loopback")
    func httpsIsAccepted() {
        let resolved = Config.resolveWidgetURL(
            environment: [:],
            registryText: #"{ "port": 4022, "pid": 5150, "url": "https://127.0.0.1:4022" }"#,
            isProcessAlive: alive
        )
        #expect(resolved.url?.absoluteString == "https://127.0.0.1:4022/widget")
    }

    // MARK: - What an open does with the webview

    @Test("an open whose URL matches what is showing loads nothing")
    func keepShowing() {
        let url = URL(string: "http://127.0.0.1:4022/widget")!
        let resolution = Config.WidgetURLResolution(
            url: url,
            source: .registry,
            registry: .won(port: 4022, pid: 5150)
        )
        #expect(Config.decideLoad(resolution, showing: url) == .keepShowing(url))
    }

    @Test("a dashboard that moved to another port is loaded on the next open")
    func movedDashboardReloads() {
        let resolution = Config.resolveWidgetURL(
            environment: [:],
            registryText: registry(port: 4022, pid: 5150),
            isProcessAlive: alive
        )
        // Showing the old port, which is what the webview holds after the
        // dashboard moved away from it.
        let decision = Config.decideLoad(resolution, showing: URL(string: Config.defaultWidgetURLString))
        #expect(decision == .load(URL(string: "http://127.0.0.1:4022/widget")!))
    }

    @Test("a registry that went away drops the panel back to the default")
    func dashboardStopped() {
        let resolution = Config.resolveWidgetURL(
            environment: [:],
            registryText: nil,
            isProcessAlive: alive
        )
        let decision = Config.decideLoad(resolution, showing: URL(string: "http://127.0.0.1:4022/widget"))
        #expect(decision == .load(URL(string: Config.defaultWidgetURLString)!))
    }

    @Test("an unresolved URL shows the offline page rather than reloading the last good one")
    func unresolvedShowsOffline() {
        let resolution = Config.resolveWidgetURL(environment: [Config.urlEnvironmentKey: "  "], registryText: nil)
        #expect(resolution.url == nil)
        #expect(Config.decideLoad(resolution, showing: URL(string: Config.defaultWidgetURLString)) == .showOfflinePage)
    }

    // MARK: - The real liveness check

    @Test("this process is alive and a pid nothing holds is not")
    func liveness() {
        #expect(ServiceRegistry.isProcessAlive(ProcessInfo.processInfo.processIdentifier))
        // 999999 is above the default kern.maxpid on macOS, so ESRCH is the
        // answer and there is no process to disturb.
        #expect(!ServiceRegistry.isProcessAlive(999_999))
        #expect(!ServiceRegistry.isProcessAlive(0))
        #expect(!ServiceRegistry.isProcessAlive(-1))
    }

    @Test("the liveness check runs against the kernel when the caller does not inject one")
    func livenessDefaultArgument() {
        // No `isProcessAlive` passed, so the real check answers, and this
        // process is running.
        let resolution = Config.resolveWidgetURL(
            environment: [:],
            registryText: registry(port: 4022, pid: ProcessInfo.processInfo.processIdentifier)
        )
        #expect(resolution.source == .registry)
        #expect(resolution.url?.absoluteString == "http://127.0.0.1:4022/widget")
    }

    @Test("reading a path that does not exist returns nil instead of throwing")
    func readingNothingIsNil() {
        // A state home pointed at a directory this test made, so the real
        // registry in the real state directory is never touched.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-dashbar-registry-test-\(UUID().uuidString)")
        #expect(
            ServiceRegistry.currentText(environment: ["XDG_STATE_HOME": scratch.path, "HOME": scratch.path]) == nil
        )
        #expect(
            ServiceRegistry.currentPath(environment: ["XDG_STATE_HOME": scratch.path, "HOME": scratch.path])
                == scratch.appendingPathComponent("oc-dash/service.json").path
        )
    }
}
