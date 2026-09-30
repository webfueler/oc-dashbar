import Foundation

/// One click on the widget's start control, end to end: find the user's login
/// shell, ask it what is on its PATH, resolve `npx` or an installed `oc-dash`,
/// spawn it once, watch long enough to hear a refusal, and walk away.
///
/// What is not in this file is the point of it. There is no retry, no timer,
/// no keep-alive, no restart and no cleanup. `oc-dash server stop` stays the
/// only thing that stops a dashboard. One spawn happens, its outcome is
/// written to the log, and this file does not think about the process again.
///
/// The one exception is named where it is, in `probe`: the login shell this
/// file spawns can be stopped if it stops answering, which is a signal to our
/// own child and to nothing else on the machine.
///
/// The pure half is separated from the half that runs things, and it is the
/// half the tests drive. `Failure` carries the whole of what a user can hit
/// and turns it into the words, because the words are the deliverable: a
/// person whose button did nothing needs to be told which thing went wrong and
/// what to type instead.
enum StartServer {
    // MARK: - The words

    /// Everything that can stop a start, and the text for each.
    ///
    /// Every case names what was tried and what came back, and most of them end
    /// with a command the person can run themselves. A message that says only
    /// "could not start the dashboard" is the one case here not worth printing.
    ///
    /// `Error` is conformed to because `Result` requires it and because these
    /// really are errors. Nothing is thrown: they are returned, so a caller
    /// has to handle each one and cannot ignore it by accident.
    enum Failure: Error, Equatable {
        /// Neither `$SHELL` nor the user record named a shell we can run.
        case noLoginShell(shellEnvironment: String?, userRecord: String?)

        /// The shell is named but the file could not be started.
        case loginShellUnrunnable(shell: String, said: String)

        /// The shell ran and failed, so its PATH is unknown.
        case loginShellFailed(shell: String, exitCode: Int32, said: String)

        /// The shell did not answer in time and was stopped. Its stdin is
        /// /dev/null, so this means a startup file taking longer than a
        /// deadline rather than a shell waiting for a keypress.
        case loginShellTimedOut(shell: String, seconds: Int)

        /// The shell answered and the answer was not the block we asked for: it
        /// finished, but with no PATH in it. Refused rather than guessed at.
        case unreadableProbe(shell: String, said: String)

        /// The common case on somebody else's machine. The PATH came back and
        /// neither binary is on it, which almost always means there is no node
        /// on the login PATH.
        case notInstalled(shell: String, path: String, entries: Int)

        /// The binary was on the PATH a moment ago and the spawn itself
        /// failed. A broken or half-removed install, not a missing one.
        case spawnFailed(executable: String, said: String)

        /// It ran and it said no. `said` is oc-dash's own explanation, which is
        /// the only text that knows what was actually wrong.
        case exitedNonZero(command: String, exitCode: Int32, seconds: Double, said: String)

        /// The lines to log, in order. Every one of them is a whole line, so
        /// every one of them gets the log's prefix.
        var message: [String] {
            let flags = Config.loginShellFlags.joined(separator: " ")
            switch self {
            case .noLoginShell(let shellEnvironment, let userRecord):
                return [
                    "start failed: no login shell to ask for a PATH, so nvm and Homebrew cannot be seen from here."
                        + " $SHELL is \(quoted(shellEnvironment)) and the user record names \(quoted(userRecord)).",
                    "  This app was launched by Finder, which hands it PATH=/usr/bin:/bin:/usr/sbin:/sbin and nothing else.",
                    "  Start the dashboard from a terminal: \(StartServer.byHand)",
                ]
            case .loginShellUnrunnable(let shell, let said):
                return [
                    "start failed: could not run the login shell \(shell): \(said)",
                    "  It is named by \(Config.loginShellFlags.joined(separator: " ")) and this app would have used it,"
                        + " so the file is missing or not executable.",
                    "  Start the dashboard from a terminal: \(StartServer.byHand)",
                ]
            case .loginShellFailed(let shell, let exitCode, let said):
                return explained(
                    headline: "start failed: \(shell) \(flags) exited \(exitCode), so its PATH is unknown.",
                    detail: said,
                    footer: "Start the dashboard from a terminal: \(StartServer.byHand)"
                )
            case .loginShellTimedOut(let shell, let seconds):
                return [
                    "start failed: \(shell) \(flags) did not answer within \(seconds)s and was stopped."
                        + " Something in a shell startup file takes longer than that.",
                    "  Start the dashboard from a terminal: \(StartServer.byHand)",
                ]
            case .unreadableProbe(let shell, let said):
                return explained(
                    headline: "start failed: \(shell) \(flags) finished without saying what its PATH is.",
                    detail: said,
                    footer: "Start the dashboard from a terminal: \(StartServer.byHand)"
                )
            case .notInstalled(let shell, let path, let entries):
                return [
                    "start failed: oc-dash is not installed, and neither is npx. Asked \(shell) \(flags) for its PATH:"
                        + " \(entries) entries, and neither \"oc-dash\" nor \"npx\" is in it.",
                    "  PATH=" + path,
                    "  A login shell that has never run a version manager has no node on it, which is the normal state"
                        + " of a machine where npm was never set up.",
                    "  Install it once, with: npm i -g \(Config.startPackageName)",
                    "  Or start the dashboard from a terminal: \(StartServer.byHand)",
                ]
            case .spawnFailed(let executable, let said):
                return [
                    "start failed: could not run \(executable): \(said)",
                    "  It was on the login PATH a moment ago, so this is a broken or half-removed install rather than"
                        + " a missing one.",
                    "  Reinstall it with: npm i -g \(Config.startPackageName)",
                ]
            case .exitedNonZero(let command, let exitCode, let seconds, let said):
                return explained(
                    headline: "start failed: \(command) exited \(exitCode) after"
                        + " \(String(format: "%.1f", seconds))s. Nothing was started.",
                    detail: said,
                    footer: "Run the same command in a terminal to see everything it printed: \(command)"
                )
            }
        }
    }

    /// The arguments the npx spawn is given: the tagged package reference and
    /// the subcommand, in one place. The page's command line is this array
    /// joined under `npx`, and the spawn hands it to `Process` unchanged, so
    /// what the page shows and what executes cannot be edited apart.
    static let npxArguments = [Config.startPackageReference] + Config.startSubcommand

    /// The command to print when the reader has to do it by hand. The same
    /// arguments the npx spawn gets, under the bare `npx` a terminal already
    /// resolves, and the same `server start` oc-dash spells in its own help.
    static let byHand = (["npx"] + npxArguments).joined(separator: " ")

    // MARK: - What to run, decided without running it

    /// A command this shell is willing to spawn, with the PATH to hand it.
    struct Command: Equatable {
        let executable: String
        let arguments: [String]
        /// The login shell's PATH. The child gets this, and the reason it has
        /// to is not cosmetic: `npx` is `#!/usr/bin/env node`, so spawning the
        /// absolute path we found while leaving PATH as Finder left it fails
        /// with `env: node: No such file or directory`. Measured, not assumed.
        let path: String
        /// Which of `Config.startBinaryNames` this is, for the log.
        let name: String

        var display: String { ([executable] + arguments).joined(separator: " ") }
    }

    /// What the login shell said, parsed.
    struct Report: Equatable {
        let path: String
        /// Absolute path per binary name, in `Config.startBinaryNames` order,
        /// nil where the shell found nothing. A name is absent rather than an
        /// empty string so a blank answer cannot be mistaken for a hit.
        let found: [String: String]
    }

    /// Parses the labelled block. nil unless the whole block arrived.
    ///
    /// `DONE` is required. A shell that died after printing `PATH` would
    /// otherwise be read as a shell with no node on it, and the message would
    /// send the reader to install something they already have.
    static func parse(_ output: String) -> Report? {
        guard output.contains("DONE") else { return nil }
        var path: String?
        var found: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            // Split on the FIRST `=` only. A PATH entry is allowed to contain
            // one, and truncating a real PATH at the first `=` inside a
            // directory name is a bug that would only show up on somebody
            // else's machine.
            let value = String(line[line.index(after: separator)...])
            if key == "PATH" {
                path = value
            }
            else if Config.startBinaryNames.contains(key), !value.isEmpty {
                found[key] = value
            }
        }
        guard let path, !path.isEmpty else { return nil }
        return Report(path: path, found: found)
    }

    /// The command, or the reason there is not one.
    ///
    /// The first name in `Config.startBinaryNames` that the shell found wins,
    /// which is what makes an installed `oc-dash` preferable to `npx`.
    static func resolve(_ report: Report, shell: String) -> Result<Command, Failure> {
        for name in Config.startBinaryNames {
            guard let executable = report.found[name] else { continue }
            let arguments =
                name == "npx" ? npxArguments : Config.startSubcommand
            return .success(Command(executable: executable, arguments: arguments, path: report.path, name: name))
        }
        return .failure(
            .notInstalled(shell: shell, path: report.path, entries: report.path.split(separator: ":").count)
        )
    }

    /// The user's login shell, or nil.
    ///
    /// `$SHELL` first, because that is what the user's own terminal uses and
    /// because a Finder-launched app does have it: measured on this machine, a
    /// Finder launch of this shell sees `SHELL=/bin/zsh` and, apart from that,
    /// nothing useful. The passwd entry is the fallback for an app started
    /// where `SHELL` is not set at all, which is the launchd case.
    ///
    /// Pure given `userShell`, so a test covers all three answers without a
    /// user record.
    static func loginShell(environment: [String: String], userShell: String?) -> String? {
        for candidate in [environment["SHELL"], userShell] {
            guard let path = candidate, path.hasPrefix("/"),
                FileManager.default.isExecutableFile(atPath: path)
            else { continue }
            return path
        }
        return nil
    }

    /// The login shell from the passwd database, or nil. The one place this
    /// file asks the operating system a question instead of reading the
    /// environment.
    static func passwdShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }

    // MARK: - Running it

    /// One start. Blocking, so the caller owns the queue: the AppDelegate
    /// calls this off the main thread because it spawns a process and waits on
    /// one, and neither belongs in a `WKNavigationDelegate` callback or on the
    /// main queue.
    ///
    /// `environment` is what the child inherits, with `PATH` replaced by the
    /// login shell's. Everything else is passed through, which is what keeps a
    /// `XDG_STATE_HOME` or a `PORT` set for this app reaching oc-dash, and is
    /// why a person who pointed the widget at a scratch dashboard gets the
    /// scratch dashboard started too.
    static func start(request: Int, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let userShell = passwdShell()
        guard let shell = loginShell(environment: environment, userShell: userShell) else {
            report(request, .noLoginShell(shellEnvironment: environment["SHELL"], userRecord: userShell))
            return
        }

        switch probe(shell: shell, environment: environment) {
        case .failure(let failure):
            report(request, failure)
        case .success(let answer):
            switch resolve(answer, shell: shell) {
            case .failure(let failure):
                report(request, failure)
            case .success(let command):
                Log.info(
                    "start request #\(request): PATH from \(shell)"
                        + " \(Config.loginShellFlags.joined(separator: " ")), running \(command.name) at \(command.executable)"
                )
                spawn(request, command, environment: environment)
            }
        }
    }

    /// Asks the login shell its questions, on a deadline.
    private static func probe(shell: String, environment: [String: String]) -> Result<Report, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = Config.loginShellFlags + [Config.loginShellScript]
        // /dev/null, because an interactive shell is allowed to want a terminal
        // and this one has none. It is also what keeps a version manager or an
        // npx prompt from sitting on a question nobody is there to answer.
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let said = CappedOutput(limit: Config.startOutputLimit)
        drain(out.fileHandleForReading, into: said)
        drain(err.fileHandleForReading, into: said)

        let finished = DispatchSemaphore(value: 0)
        // Set before `run()`, so the semaphore cannot be missed by a shell that
        // exits before this thread reaches `wait`.
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        }
        catch {
            return .failure(.loginShellUnrunnable(shell: shell, said: reason(for: error)))
        }

        if finished.wait(timeout: .now() + Config.loginShellTimeout) == .timedOut {
            // THE ONE SIGNAL THIS SHELL EVER SENDS. It goes to the login shell
            // spawned a few lines above, whose executable is the user's own
            // shell and whose only argument is our own script, and it is sent
            // because a shell that never answers is a process leaked on every
            // click. It cannot reach a dashboard: this shell has never held a
            // dashboard's pid and has no code that could.
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            return .failure(.loginShellTimedOut(shell: shell, seconds: Int(Config.loginShellTimeout)))
        }

        // A pipe reaches EOF a turn or two after the process does, so a short
        // wait is the difference between a message that explains itself and
        // one that says `exited 1` and nothing else.
        let output = said.waitForDrain()
        guard let answer = parse(output) else {
            return output.contains("DONE")
                ? .failure(.unreadableProbe(shell: shell, said: output))
                : .failure(.loginShellFailed(shell: shell, exitCode: process.terminationStatus, said: output))
        }
        return .success(answer)
    }

    /// Spawns the command once, watches it for a refusal, and forgets it.
    ///
    /// The watch is a deadline and nothing else: no poll, no callback that
    /// fires again, no second spawn. A process still running when the deadline
    /// arrives is a process that started, because the two things that can go
    /// wrong here both end in an early exit with a non-zero status.
    private static func spawn(_ request: Int, _ command: Command, environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        // Finder's PATH, not the login shell's, and `npx` dies on it. The one
        // environment change the child gets.
        process.environment = environment.merging([("PATH", command.path)]) { _, login in login }
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let said = CappedOutput(limit: Config.startOutputLimit)
        let ended = DispatchSemaphore(value: 0)
        let outDrained = drain(out.fileHandleForReading, into: said)
        let errDrained = drain(err.fileHandleForReading, into: said)
        let started = Date()

        process.terminationHandler = { finished in
            // Reaping, and that is all. The exit status is read and written to
            // the log; nothing is sent to the process and nothing is decided
            // about any dashboard.
            StartServer.forget(finished)
            let text = said.waitForDrain(after: [outDrained, errDrained])
            let seconds = Date().timeIntervalSince(started)
            if finished.terminationStatus == 0 {
                Log.info(
                    "start request #\(request): \(command.display) exited 0 after"
                        + " \(String(format: "%.1f", seconds))s"
                )
                say(request, text)
            }
            else {
                report(
                    request,
                    .exitedNonZero(
                        command: command.display,
                        exitCode: finished.terminationStatus,
                        seconds: seconds,
                        said: text
                    )
                )
            }
            ended.signal()
        }
        // Held so Foundation reaps the process rather than leaving init to find
        // it, and so the closure above can time itself. Holding it is not
        // keeping it alive: nothing here asks about it again.
        watched.withLock { $0.append(process) }

        do {
            try process.run()
        }
        catch {
            watched.withLock { $0.removeAll { $0 === process } }
            report(request, .spawnFailed(executable: command.executable, said: reason(for: error)))
            return
        }

        if ended.wait(timeout: .now() + Config.startWatchTimeout) == .timedOut {
            // Still running after the window. This is the started case, and its
            // shape depends on which oc-dash answered: the published package
            // runs the server in this very process, and the CLI in the checkout
            // detaches one and exits 0. Either way the answer is the same, and
            // either way we stop looking here.
            Log.info(
                "start request #\(request): \(command.display) is still running after"
                    + " \(Int(Config.startWatchTimeout))s, which is what a started server looks like."
                    + " Not watching it again: oc-dash server stop is the only thing that stops it."
            )
            say(request, said.text)
        }
    }

    /// Writes a failure and the child's own words under it.
    private static func report(_ request: Int, _ failure: Failure) {
        let lines = failure.message
        Log.info("start request #\(request) \(lines.first ?? "failed")")
        for line in lines.dropFirst() {
            Log.info(line)
        }
    }

    /// Echoes whatever the child said on its way out, labelled so a line of it
    /// cannot be mistaken for one of ours.
    private static func say(_ request: Int, _ text: String) {
        let lines = StartServer.quoteLines(text)
        guard !lines.isEmpty else { return }
        Log.info("start request #\(request), the child said:")
        for line in lines {
            Log.info("  \(line)")
        }
    }

    /// Child output as log lines: trimmed, empty lines dropped, capped, so a
    /// stack trace cannot be mistaken for twelve separate problems. Twelve is
    /// the length of oc-dash's own longest refusal, so its guidance arrives
    /// whole rather than cut in the middle of a sentence.
    static func quoteLines(_ text: String, limit: Int = 12) -> [String] {
        let trimmed =
            text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        for line in trimmed {
            if out.count == limit { break }
            out.append(line)
        }
        return out
    }

    // MARK: - Output plumbing

    /// A child's output, kept to a cap, read to EOF on threads of its own.
    ///
    /// The cap is on what is kept, not on what is read. A child that fills a
    /// pipe nobody drains blocks forever, and a blocked dashboard is a worse
    /// outcome than a truncated error message.
    final class CappedOutput: @unchecked Sendable {
        private let limit: Int
        private let lock = NSLock()
        private var data = Data()

        init(limit: Int) {
            self.limit = limit
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            let room = limit - data.count
            if room > 0 { data.append(chunk.prefix(room)) }
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }

        /// The text as it stands, plus whatever arrives in the next moment.
        func waitForDrain(after semaphores: [DispatchSemaphore] = [], limit: TimeInterval = 0.5) -> String {
            for semaphore in semaphores {
                _ = semaphore.wait(timeout: .now() + limit)
            }
            return text
        }
    }

    /// Reads one pipe to EOF on its own thread. The returned semaphore is
    /// signalled when that pipe closes.
    @discardableResult
    private static func drain(_ handle: FileHandle, into collector: CappedOutput) -> DispatchSemaphore {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collector.append(chunk)
            }
            done.signal()
        }
        return done
    }

    /// Processes we are still watching, so Foundation reaps them. Never read
    /// for any other purpose: nothing here asks whether one of them is alive,
    /// and nothing would act on the answer.
    private static let watched = Mutex<[Process]>([])

    private static func forget(_ process: Process) {
        watched.withLock { $0.removeAll { $0 === process } }
    }

    // MARK: - Message helpers

    private static func explained(headline: String, detail: String, footer: String) -> [String] {
        var out = [headline]
        out.append(contentsOf: quoteLines(detail).map { "  it said: \($0)" })
        out.append("  \(footer)")
        return out
    }

    private static func quoted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "unset" }
        return "set to \(value)"
    }

    private static func reason(for error: Error) -> String {
        (error as NSError).localizedDescription
    }

    /// A value behind a lock. Three lines instead of a dependency, and the only
    /// shared mutable state in this file is a list of processes we are not
    /// supervising.
    final class Mutex<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func withLock<T>(_ body: (inout Value) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }
}
