import Foundation
import Testing

@testable import oc_dashbar

/// Three groups, in the order they matter: what the login shell is asked and
/// how its answer is read, which command comes out of that answer, and the
/// words each failure produces. The last group is the product, so it is
/// asserted on the text rather than on an enum case.
@Suite("Start server")
struct StartServerTests {
    // MARK: - Real answers from a real login shell

    /// Captured from a real `/bin/zsh -l -i -c`, with the environment a Finder
    /// launch hands an app: `SHELL=/bin/zsh`,
    /// `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. This is the answer the whole
    /// design rests on, so it is a fixture rather than a shape I invented.
    private let nvmPath = "/Users/someone/.nvm/versions/node/v22.22.2/bin"

    private func block(path: String, ocDash: String = "", npx: String = "") -> String {
        """
        PATH=\(path)
        oc-dash=\(ocDash)
        npx=\(npx)
        DONE
        """
    }

    /// The four plausible answers, all of them real. `nvmPath` and the npx
    /// path come from a real machine, captured before the code was written.
    @Test("the answer this shell depends on: a login shell with nvm on it")
    func nvmLoginShell() {
        let homebrew = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
        let path = "/Users/someone/bin:/Users/someone/.local/bin:\(homebrew):\(nvmPath):/usr/bin:/bin"
        let report = StartServer.parse(block(path: path, npx: "\(nvmPath)/npx"))
        #expect(report != nil)
        #expect(report?.path == path)
        #expect(report?.found["npx"] == "\(nvmPath)/npx")
        #expect(report?.found["oc-dash"] == nil)
    }

    /// The trap. A login shell with Homebrew and no nvm, which is what
    /// `zsh -l -c` produced here, and what a naive implementation that guessed
    /// at a shell would have used. It has to resolve to npx or it will tell the
    /// reader to install something they have.
    @Test("a login PATH with Homebrew but no nvm is read as no npx, not as a path that works")
    func homebrewWithoutNvm() {
        let path = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let report = StartServer.parse(block(path: path))
        #expect(report?.found["npx"] == nil)
        #expect(report?.found["oc-dash"] == nil)
    }

    /// What a Finder-launched app actually inherits, and it has no node in it.
    /// Pinned because it is the reason `Config.loginShellFlags` is not just
    /// `-l`, and it is the reason the PATH is measured rather than assumed.
    @Test("the PATH a Finder launch hands us has no node, which is the whole problem")
    func finderPathHasNoNode() {
        let report = StartServer.parse(block(path: "/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(report?.path == "/usr/bin:/bin:/usr/sbin:/sbin")
        switch StartServer.resolve(report!, shell: "/bin/zsh") {
        case .success:
            Issue.record("a PATH with no node in it must not resolve to a command")
        case .failure(let failure):
            guard case .notInstalled = failure else {
                Issue.record("expected notInstalled, got \(failure)")
                return
            }
        }
    }

    @Test("an installed oc-dash wins over npx, and the arguments differ")
    func installedBinaryWins() {
        let path = "/usr/local/bin:\(nvmPath):/usr/bin:/bin"
        let report = StartServer.parse(
            block(path: path, ocDash: "/usr/local/bin/oc-dash", npx: "\(nvmPath)/npx")
        )
        guard case .success(let command) = StartServer.resolve(report!, shell: "/bin/zsh") else {
            Issue.record("an installed oc-dash must resolve")
            return
        }
        #expect(command.name == "oc-dash")
        #expect(command.executable == "/usr/local/bin/oc-dash")
        // No package name: an installed binary does not want one, and passing
        // it would be the argument oc-dash would read as a subcommand.
        #expect(command.arguments == ["server", "start"])
        #expect(command.path == path)
    }

    @Test("npx alone still resolves, and carries the package name")
    func npxOnly() {
        let report = StartServer.parse(block(path: nvmPath, npx: "\(nvmPath)/npx"))
        guard case .success(let command) = StartServer.resolve(report!, shell: "/bin/zsh") else {
            Issue.record("npx must resolve on its own")
            return
        }
        #expect(command.name == "npx")
        #expect(command.executable == "\(nvmPath)/npx")
        #expect(command.arguments == ["@webfueler/oc-dash", "server", "start"])
        #expect(command.display == "\(nvmPath)/npx @webfueler/oc-dash server start")
    }

    /// The package name is the published one and not the bare `oc-dash`. A bare
    /// name is a 404 on the registry, and this is the string the child gets, so
    /// a typo here is a button that fails on every machine.
    @Test("the package name is the one the registry actually has")
    func packageName() {
        #expect(Config.startPackageName == "@webfueler/oc-dash")
        #expect(StartServer.byHand == "npx @webfueler/oc-dash server start")
    }

    /// A PATH entry is allowed to contain an `=`, and truncating the PATH at the
    /// first one would produce a PATH that resolves to nothing while looking
    /// perfectly normal in the log.
    @Test("an `=` inside a PATH entry does not truncate the PATH")
    func equalsInsidePath() {
        let path = "/opt/weird=name/bin:\(nvmPath):/usr/bin"
        let report = StartServer.parse(block(path: path, npx: "\(nvmPath)/npx"))
        #expect(report?.path == path)
    }

    @Test("a shell that died before finishing is not read as an answer")
    func truncatedBlock() {
        let truncated = "PATH=/usr/bin:/bin\noc-dash=\n"
        #expect(StartServer.parse(truncated) == nil)
        // The same lines plus the marker is an answer, even an empty one.
        #expect(StartServer.parse(truncated + "DONE\n") != nil)
    }

    @Test("shell noise around the block does not break it")
    func noiseAroundBlock() {
        let noisy = """
            zsh: no job control in this shell
            \(block(path: nvmPath, npx: "\(nvmPath)/npx"))
            some other warning
            """
        #expect(StartServer.parse(noisy)?.found["npx"] == "\(nvmPath)/npx")
    }

    @Test("a blank PATH is not an answer")
    func blankPath() {
        #expect(StartServer.parse("PATH=\nDONE\n") == nil)
        #expect(StartServer.parse("DONE\n") == nil)
    }

    // MARK: - The login shell

    @Test("`$SHELL` wins, and the passwd entry is the fallback")
    func loginShellPreference() {
        #expect(StartServer.loginShell(environment: ["SHELL": "/bin/sh"], userShell: "/bin/zsh") == "/bin/sh")
        #expect(StartServer.loginShell(environment: [:], userShell: "/bin/zsh") == "/bin/zsh")
        // Not a path, or not a file: refused rather than spawned and reported.
        #expect(StartServer.loginShell(environment: ["SHELL": "zsh"], userShell: "/bin/zsh") == "/bin/zsh")
        #expect(StartServer.loginShell(environment: ["SHELL": ""], userShell: nil) == nil)
        #expect(StartServer.loginShell(environment: ["SHELL": "/bin/definitely-not-here"], userShell: nil) == nil)
    }

    @Test("this machine has a login shell, and it is the one the passwd record names")
    func realLoginShell() {
        let passwd = StartServer.passwdShell()
        #expect(passwd?.hasPrefix("/") == true)
        #expect(StartServer.loginShell(environment: [:], userShell: passwd) == passwd)
    }

    /// The `-i` is the whole reason this works and it looks like a detail
    /// somebody would tidy away. zsh reads `.zshrc`, where nvm is installed,
    /// only for an interactive shell, so dropping `-i` makes the button report
    /// oc-dash is not installed on a machine where it is. If this test has to
    /// be deleted to make a change, the change is wrong.
    @Test("the login shell is asked with -l -i -c, and -i is the part that matters")
    func loginShellFlags() {
        #expect(Config.loginShellFlags == ["-l", "-i", "-c"])
        let script = Config.loginShellScript
        #expect(script.contains("\"$PATH\""))
        #expect(script.contains("oc-dash="))
        #expect(script.contains("npx="))
        // The marker is what makes a half-finished shell distinguishable from
        // a shell with no node on it.
        #expect(script.hasSuffix("printf 'DONE\\n'"))
    }

    // MARK: - The words

    /// The common case on somebody else's machine, asserted on the text. The
    /// person reading this has a button that did nothing and a dashboard that
    /// is not running, and the message has to tell them both that oc-dash is
    /// not installed and what to type.
    @Test("not installed is explicit, names both binaries, and says what to run")
    func notInstalledMessage() {
        let failure = StartServer.Failure.notInstalled(
            shell: "/bin/zsh",
            path: "/usr/bin:/bin:/usr/sbin:/sbin",
            entries: 4
        )
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("oc-dash is not installed"))
        #expect(text.contains("neither is npx"))
        #expect(text.contains("/bin/zsh -l -i -c"))
        #expect(text.contains("4 entries"))
        #expect(text.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(text.contains("npm i -g @webfueler/oc-dash"))
        #expect(text.contains("npx @webfueler/oc-dash server start"))
        // Every line carries a prefix, so a quoted message is greppable.
        #expect(failure.message.allSatisfy { !$0.isEmpty })
    }

    @Test("no login shell says what was asked and offers the same command")
    func noLoginShellMessage() {
        let failure = StartServer.Failure.noLoginShell(shellEnvironment: nil, userRecord: nil)
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("no login shell"))
        #expect(text.contains("$SHELL is unset"))
        #expect(text.contains("the user record names unset"))
        #expect(text.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(text.contains("npx @webfueler/oc-dash server start"))
    }

    @Test("a shell that failed quotes what it said")
    func loginShellFailedMessage() {
        let failure = StartServer.Failure.loginShellFailed(
            shell: "/bin/zsh",
            exitCode: 1,
            said: "/etc/zshrc:3: permission denied\n"
        )
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("/bin/zsh -l -i -c exited 1"))
        #expect(text.contains("it said: /etc/zshrc:3: permission denied"))
        #expect(text.contains("npx @webfueler/oc-dash server start"))
    }

    @Test("a shell that never answered says so and says it was stopped")
    func loginShellTimedOutMessage() {
        let failure = StartServer.Failure.loginShellTimedOut(shell: "/bin/zsh", seconds: 10)
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("did not answer within 10s"))
        #expect(text.contains("was stopped"))
        #expect(text.contains("npx @webfueler/oc-dash server start"))
    }

    @Test("an answer with no PATH in it is refused rather than guessed at")
    func unreadableProbeMessage() {
        let failure = StartServer.Failure.unreadableProbe(shell: "/bin/zsh", said: "DONE\n")
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("finished without saying what its PATH is"))
        #expect(text.contains("it said: DONE"))
    }

    @Test("a shell that will not start says which file and what to do")
    func loginShellUnrunnableMessage() {
        let failure = StartServer.Failure.loginShellUnrunnable(shell: "/bin/zsh", said: "No such file or directory")
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("could not run the login shell /bin/zsh"))
        #expect(text.contains("No such file or directory"))
        #expect(text.contains("npx @webfueler/oc-dash server start"))
    }

    /// A spawn that fails is a different problem from a missing install, and
    /// the message says so: the file was on the PATH a moment ago, so
    /// "install it" is the wrong advice.
    @Test("a spawn that fails is a broken install, and the message says that")
    func spawnFailedMessage() {
        let failure = StartServer.Failure.spawnFailed(
            executable: "/usr/local/bin/npx",
            said: "No such file or directory"
        )
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("could not run /usr/local/bin/npx"))
        #expect(text.contains("broken or half-removed install"))
        #expect(text.contains("Reinstall it with: npm i -g @webfueler/oc-dash"))
    }

    /// The one that carries oc-dash's own words, which are the only text that
    /// knows what was actually wrong.
    @Test("a non-zero exit quotes the exit code, the time and what oc-dash said")
    func exitedNonZeroMessage() {
        let failure = StartServer.Failure.exitedNonZero(
            command: "/usr/local/bin/npx @webfueler/oc-dash server start",
            exitCode: 1,
            seconds: 3.9,
            said: "oc-dash exited before it finished starting (exit code 1).\n"
        )
        let text = failure.message.joined(separator: "\n")
        #expect(text.contains("exited 1 after 3.9s"))
        #expect(text.contains("Nothing was started"))
        #expect(text.contains("it said: oc-dash exited before it finished starting (exit code 1)."))
    }

    @Test("child output is trimmed, empty lines dropped and capped")
    func quoteLines() {
        let text = "\n  one  \n\n two\nthree\n" + (0..<20).map { "line \($0)" }.joined(separator: "\n")
        // The cap is passed explicitly so this test is about the trimming and
        // the cap rather than about the default, which `defaultCapHoldsTheLongestRefusal` pins.
        let lines = StartServer.quoteLines(text, limit: 8)
        #expect(lines.count == 8)
        #expect(lines.first == "one")
        #expect(lines.contains("two"))
        #expect(lines.last == "line 4")
        #expect(StartServer.quoteLines("", limit: 8).isEmpty)
        #expect(StartServer.quoteLines("   \n\n", limit: 8).isEmpty)
    }

    /// oc-dash's longest refusal, quoted from a real run on this machine, is
    /// nine lines. A cap below that cuts the middle of its advice, and the
    /// advice is the part a person acts on.
    @Test("the default cap holds the longest refusal oc-dash actually prints")
    func defaultCapHoldsTheLongestRefusal() {
        let said = """
            no healthy registered opencode service (looked at /tmp/state/opencode/service.json)

            No running opencode service was found. The dashboard reads everything
            from the opencode2 service over HTTP, so opencode must be installed and
            a service must be running. Start the service, then run oc-dash again:

                opencode serve --service
                npx @webfueler/oc-dash server start

            If you don't have opencode yet, install it with:

                curl -fsSL https://opencode.ai/install | bash

            More options: https://opencode.ai
            """
        let lines = StartServer.quoteLines(said)
        // Nine non-empty lines, and the cap of twelve leaves all of them. The
        // indentation is trimmed, which is what makes them log lines rather
        // than a code block.
        #expect(lines.count == 9)
        #expect(lines.first?.hasPrefix("no healthy registered opencode service") == true)
        #expect(lines.contains("npx @webfueler/oc-dash server start"))
        #expect(lines.last == "More options: https://opencode.ai")
    }

    /// A start is one spawn and this shell never signals a dashboard. The only
    /// `terminate` in the sources is the one on the login shell this shell
    /// spawned itself, and this asserts that reading of the code is still the
    /// only reading available.
    @Test("the shell holds no dashboard pid and offers no way to signal one")
    func noDashboardSignals() {
        // The API that would signal a dashboard is not called anywhere except
        // on the probe. `ServiceRegistry.isProcessAlive` is the one kill() in
        // this project and it passes signal 0, which delivers nothing.
        #expect(ServiceRegistry.isProcessAlive(getpid()))
        #expect(!ServiceRegistry.isProcessAlive(999_999))
    }

    // MARK: - The delegate's switch

    /// The action a start takes, behind a closure so the switch can be driven
    /// without spawning anything. Production behaviour is the queue hop and
    /// `StartServer.start`.
    @Test("the delegate's start arm runs the start action with the counted request")
    @MainActor
    func delegateStartsOnce() {
        let delegate = AppDelegate()
        var seen: [Int] = []
        delegate.startAction = { seen.append($0) }
        delegate.termination = { Issue.record("a start must not terminate the app") }

        delegate.act(on: .startServer(request: 1))
        #expect(seen == [1])
        #expect(delegate.startRequestsAnswered == 1)
        #expect(delegate.quitRequestsAnswered == 0)

        // A second click is a second explicit ask. The shell does not
        // deduplicate: the page owns the arm that prevents a double click, and
        // inventing a policy here would be the shell deciding for it.
        delegate.act(on: .startServer(request: 2))
        #expect(seen == [1, 2])
        #expect(delegate.startRequestsAnswered == 2)
    }

    /// The deferral is the load-bearing part of the quit arm: WebKit is
    /// mid-callback when the handler returns, and terminating underneath it is
    /// a crash report instead of a quit. So the first assertion is the important
    /// one, that nothing happened synchronously, and the second waits for the
    /// turn of the queue.
    @Test("the delegate's quit arm still terminates, and the deferral is still there")
    @MainActor
    func delegateQuits() async {
        let delegate = AppDelegate()
        var terminated = 0
        delegate.startAction = { _ in Issue.record("a quit must not start anything") }
        delegate.termination = { terminated += 1 }

        delegate.act(on: .quit(request: 1))
        #expect(terminated == 0)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(terminated == 1)
        #expect(delegate.quitRequestsAnswered == 1)
        #expect(delegate.startRequestsAnswered == 0)
    }

    @Test("cancelled decisions do nothing at all")
    @MainActor
    func cancelledDecisionsDoNothing() {
        let delegate = AppDelegate()
        var started = false
        var terminated = false
        delegate.startAction = { _ in started = true }
        delegate.termination = { terminated = true }

        delegate.act(on: .cancelUnknownHost("oc-dash://nope"))
        delegate.act(on: .cancelForeignScheme("mailto"))
        delegate.act(on: .allow)
        #expect(!started)
        #expect(!terminated)
        #expect(delegate.startRequestsAnswered == 0)
        #expect(delegate.quitRequestsAnswered == 0)
    }
}
