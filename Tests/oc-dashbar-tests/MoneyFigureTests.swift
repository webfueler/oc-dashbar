import AppKit
import Foundation
import Testing

@testable import oc_dashbar

/// Two things are pinned here, and they are the two things that could rot.
///
/// The first is the contract with the server: this exact request, and `costText`
/// reaching the title with nothing done to it on the way. The string is the
/// number, by the Captain's ruling, and the whole reason is in the project:
/// `Intl.NumberFormat` rounds ties away from zero and neither
/// `String(format:)` nor `NumberFormatter` reproduces that, so a formatter on
/// this side would be a correctness risk rather than a tidy-up.
///
/// The second is the pair of rules a slow or broken server puts under
/// pressure: at most one request in flight, and every failure hides rather than
/// showing a placeholder or a stale figure.
///
/// Nothing here needs a network. The request is a pure function of a resolved
/// URL, the title is a pure function of a body, and the tick is driven with the
/// fetch replaced by a recorder, so a hung server is a recorder that never calls
/// back. AppKit is the only part left untested, and it is only a write onto
/// `NSStatusItem.button.title`.
@Suite("Menu bar money")
struct MoneyFigureTests {
    /// A response as URLSession would hand it over: body, status, and a
    /// transport failure or nil. Every hide condition is reachable through this.
    private func title(
        _ body: String? = nil,
        status: Int? = 200,
        transportFailure: String? = nil
    ) -> MoneyFigure.Title {
        MoneyFigure.title(
            body: body.map { Data($0.utf8) },
            statusCode: status,
            transportFailure: transportFailure
        )
    }

    // MARK: - The request

    /// The contract URL, spelled out. Written with the literal on both sides
    /// because this string is shared with oc-dash and `Config` can always be
    /// changed to agree with itself.
    @Test("the money request is GET /api/summary?range=today&context=none on the default port")
    func contractURL() throws {
        let widget = try #require(URL(string: "http://127.0.0.1:4021/widget"))
        let summary = try #require(Config.summaryURL(widgetBase: widget))
        #expect(summary.absoluteString == "http://127.0.0.1:4021/api/summary?range=today&context=none")
        #expect(Config.summaryPath == "/api/summary")
        #expect(Config.summaryRangeKey == "range")
        #expect(Config.summaryRangeToday == "today")
        #expect(Config.summaryContextKey == "context")
        // `context=none` is not cosmetic. It is what skips the server's second
        // stats call, the one that feeds a chart this shell does not draw.
        #expect(Config.summaryContextNone == "none")
        #expect(Config.summaryQuery == "range=today&context=none")
    }

    /// Two of the handler's three parameters, and the two that are sent. The
    /// third, `project`, is not sent, which is the documented way to ask for no
    /// per-project work, so an item named `project` here is a bug rather than a
    /// rounding of this.
    @Test("the query carries range and context and nothing else, so no per-project work is asked for")
    func queryCarriesTwoParameters() throws {
        let widget = try #require(URL(string: "http://127.0.0.1:4021/widget"))
        let summary = try #require(Config.summaryURL(widgetBase: widget))
        let components = try #require(URLComponents(url: summary, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        #expect(items.map(\.name) == ["range", "context"])
        #expect(items.map(\.value) == ["today", "none"])
        #expect(components.path == "/api/summary")
        #expect(components.fragment == nil)
    }

    /// The load-bearing derivation. The figure and the panel are one resolution,
    /// so they cannot end up reading two different servers and disagreeing about
    /// what today cost.
    @Test("the figure asks the server the panel resolved, never a second port")
    func sameServerAsThePanel() throws {
        // Through the override, which is how a test points the panel somewhere.
        let overridden = Config.resolvedWidgetURL(
            environment: [Config.urlEnvironmentKey: "http://127.0.0.1:4046/widget"]
        )
        #expect(
            Config.summaryURL(widgetBase: overridden)?.absoluteString
                == "http://127.0.0.1:4046/api/summary?range=today&context=none"
        )

        // Through the registry, which is how a real second dashboard is found.
        let registry = Config.resolveWidgetURL(
            environment: [:],
            registryText: #"{ "port": 4046, "pid": 5150, "url": "http://127.0.0.1:4046" }"#,
            isProcessAlive: { _ in true }
        )
        #expect(registry.url?.absoluteString == "http://127.0.0.1:4046/widget")
        #expect(
            Config.summaryURL(widgetBase: registry.url)?.absoluteString
                == "http://127.0.0.1:4046/api/summary?range=today&context=none"
        )

        // And through the fallback, so all three steps of the precedence are
        // covered rather than the two a test happens to reach first.
        let fallback = Config.resolvedWidgetURL(environment: [:])
        #expect(
            Config.summaryURL(widgetBase: fallback)?.absoluteString
                == "http://127.0.0.1:4021/api/summary?range=today&context=none"
        )
    }

    /// Only the path is allowed to differ between the two URLs. Asserted on the
    /// parts, because comparing the strings would pass even if the ports were
    /// both numbers that happened to look alike.
    @Test("the figure and the panel differ in their path and in nothing else")
    func oneOrigin() throws {
        for base in [
            "http://127.0.0.1:4021/widget",
            "http://localhost:4046/widget",
            "https://127.0.0.1:4046/widget",
        ] {
            let widget = try #require(URL(string: base))
            let summary = try #require(Config.summaryURL(widgetBase: widget))
            let widgetParts = try #require(URLComponents(url: widget, resolvingAgainstBaseURL: false))
            let summaryParts = try #require(URLComponents(url: summary, resolvingAgainstBaseURL: false))
            #expect(widgetParts.scheme == summaryParts.scheme, "\(base)")
            #expect(widgetParts.host == summaryParts.host, "\(base)")
            #expect(widgetParts.port == summaryParts.port, "\(base)")
            #expect(widgetParts.path != summaryParts.path, "\(base)")
        }
    }

    /// A resolved URL carrying a path, a query or a fragment still yields the
    /// same summary URL instead of nesting them, which is what `widgetURL(base:)`
    /// does in the other direction.
    @Test("a base with a path, a query or a fragment does not nest them")
    func baseCarriesExtras() throws {
        for base in [
            "http://127.0.0.1:4046/",
            "http://127.0.0.1:4046/some/deep/path",
            "http://127.0.0.1:4046/widget?theme=dark",
            "http://127.0.0.1:4046/widget#anchor",
            "http://127.0.0.1:4046/a/b?c=1&d=2#e",
        ] {
            let widget = try #require(URL(string: base))
            #expect(
                Config.summaryURL(widgetBase: widget)?.absoluteString
                    == "http://127.0.0.1:4046/api/summary?range=today&context=none",
                "base \(base)"
            )
        }
    }

    /// No server, or a server this shell will not speak to, means no request.
    /// Both are the same answer the panel gives: nothing to show, logged, and
    /// never a request to a scheme that has no HTTP in it.
    @Test("no widget URL, and no http or https widget URL, means no request to make")
    func noUsableServer() {
        #expect(Config.summaryURL(widgetBase: nil) == nil)
        for refused in [
            "file:///tmp/widget",
            "oc-dash://quit",
            "oc-dash://open",
            "ftp://127.0.0.1:4046/widget",
            "about:blank",
        ] {
            // `URL(string:)` keeps these, and the panel would try them, which is
            // exactly why the figure has to decide rather than pass them on.
            guard let url = URL(string: refused) else { continue }
            #expect(Config.summaryURL(widgetBase: url) == nil, "\(refused) must not be asked")
        }
        #expect(Config.moneyRequestSchemes == ["http", "https"])
        // A scheme in either case is the same request, so it is not a typo. What
        // is asserted is that it resolves, not how Foundation chooses to
        // re-spell the scheme on the way out.
        let shouted = Config.summaryURL(widgetBase: URL(string: "HTTP://127.0.0.1:4046/widget"))
        #expect(shouted?.path == "/api/summary")
        #expect(shouted?.host == "127.0.0.1")
    }

    // MARK: - The string, untouched

    /// The headline case the brief asks for: a trailing zero and an awkward
    /// magnitude, arriving byte for byte.
    @Test("a trailing zero and seven figures survive byte for byte")
    func awkwardMagnitude() {
        let body = #"{"degraded":false,"costText":"$1,234,567.90"}"#
        #expect(title(body) == .show("$1,234,567.90"))
        #expect(title(body) == .show("$1,234,567.90"))
    }

    /// Every one of these has a `data.cost` beside it that a Swift formatter
    /// would render differently, so this test fails the moment anyone parses the
    /// number out of the payload and formats it here instead of showing the
    /// string.
    ///
    /// The pairs, and what a reimplementation would print:
    ///
    /// | cost | costText | a reimplementation |
    /// | --- | --- | --- |
    /// | `0` | `"$0.00"` | nothing at all, if it compared against zero |
    /// | `9.5` | `"$9.50"` | `"$9.5"`, from string interpolation |
    /// | `0.4454` | `"$0.45"` | `"$0.44"` from a half-even formatter |
    /// | `-0.4454` | `"-$0.45"` | `"-0.44"`, and the wrong sign placement |
    /// | `0.0042` | `"<$0.01"` | `"$0.00"`, because under a cent is a shape only `Intl` prints |
    /// | `1234567.895` | `"$1,234,567.90"` | `"$1234567.89"`, wrong grouping and wrong cent |
    /// | `170.23707184240106` | `"$170.24"` | `"$170.24"`, the one case it would get right |
    @Test("the string wins over the number, on every value the two would disagree about")
    func stringWinsOverNumber() {
        let cases: [(cost: String, text: String)] = [
            ("0", "$0.00"),
            ("-0", "$0.00"),
            ("9.5", "$9.50"),
            ("0.4454", "$0.45"),
            ("-0.4454", "-$0.45"),
            ("0.0042", "<$0.01"),
            ("-0.0042", "<-$0.01"),
            ("1234567.895", "$1,234,567.90"),
            ("7.5559303280000005", "$7.56"),
            ("170.23707184240106", "$170.24"),
        ]
        for testCase in cases {
            let body = #"{"degraded":false,"data":{"cost":\#(testCase.cost)},"costText":"\#(testCase.text)"}"#
            #expect(title(body) == .show(testCase.text), "cost \(testCase.cost) must display as \(testCase.text)")
        }
    }

    /// Byte identity, not visual identity. `Intl` can emit a narrow no-break
    /// space as its group separator depending on the locale data it is given,
    /// and a shell that normalised whitespace, trimmed it, or round-tripped the
    /// string through a formatter would silently change the glyphs in the
    /// Captain's menu bar while every screenshot still looked right.
    @Test("odd whitespace in the string is not tidied up")
    func whitespaceIsNotTidied() {
        let cases: [String: String] = [
            "regular comma": "$1,234.50",
            "no-break space": "$1\u{00A0}234.50",
            "thin space": "$1\u{202F}234.50",
            "space after the symbol": "$ 0.00",
        ]
        for (name, text) in cases {
            // Escaped for the JSON rather than typed in, so the file stays ASCII
            // and the character under test is the one the decoder produces.
            let escaped =
                text
                .replacingOccurrences(of: "\u{00A0}", with: "\\u00a0")
                .replacingOccurrences(of: "\u{202F}", with: "\\u202f")
            let body = #"{"degraded":false,"costText":"\#(escaped)"}"#
            #expect(title(body) == .show(text), "\(name) must survive unchanged")
        }
        // Not a currency symbol in front of it, not a digit count, nothing this
        // shell has any business correcting.
        #expect(title(#"{"degraded":false,"costText":"1 234,50 EUR"}"#) == .show("1 234,50 EUR"))
    }

    /// The real payload, captured from a scratch server by mission 099 and copied
    /// in whole. It matters that it is the real shape: `costText` is a top-level
    /// sibling of `data` rather than inside it, and this is the only test that
    /// would notice if somebody read it from the wrong place.
    @Test("the captured response from the server decodes to the string it carries")
    func capturedResponse() {
        let body = """
            {
              "degraded": false,
              "range": { "preset": "today", "from": 1790809200000, "to": 1790878956188 },
              "timezone": "Europe/Lisbon",
              "data": {
                "range": { "from": 1790809200000, "to": 1790878956188 },
                "sessions": 3,
                "subagents": 31,
                "prompts": 17,
                "steps": 2724,
                "tokens": {
                  "input": 9323101,
                  "output": 1414457,
                  "reasoning": 725181,
                  "cache": { "read": 299842642, "write": 0 }
                },
                "cost": 0,
                "tools": {
                  "mode": "summary",
                  "totals": { "calls": 2956, "succeeded": 2862, "failed": 93, "unfinished": 1 }
                },
                "activeDays": 1,
                "streak": 1,
                "activity": [ { "date": "2026-10-01", "steps": 2724 } ],
                "models": [
                  {
                    "model": { "id": "space-bunny-free", "providerID": "opencode-go", "variant": "max" },
                    "steps": 2724,
                    "tokens": {
                      "input": 9323101,
                      "output": 1414457,
                      "reasoning": 725181,
                      "cache": { "read": 299842642, "write": 0 }
                    },
                    "cost": 0
                  }
                ]
              },
              "costText": "$0.00"
            }
            """
        // `$0.00` because the model is unpriced, and `$0.00` is the Captain's
        // ruling rather than a bug. There is no branch here for an unpriced
        // model and none for an empty day, and this is the test that says so.
        #expect(title(body) == .show("$0.00"))
    }

    /// Nothing but `degraded` and `costText` is read, so nothing in `data` can
    /// make the figure appear or vanish. A body with no `data` at all still
    /// shows, and a `data` of the wrong type is not even noticed.
    @Test("data is not read, so it cannot decide the title")
    func dataIsNotRead() {
        #expect(title(#"{"degraded":false,"costText":"$7.56"}"#) == .show("$7.56"))
        #expect(title(#"{"degraded":false,"data":null,"costText":"$7.56"}"#) == .show("$7.56"))
        #expect(title(#"{"degraded":false,"data":"not an object","costText":"$7.56"}"#) == .show("$7.56"))
        // Unknown keys are not an error either, so a server that grows a field
        // does not make the figure disappear.
        #expect(title(#"{"degraded":false,"costText":"$7.56","somethingNew":[1,2,3]}"#) == .show("$7.56"))
    }

    // MARK: - The four hide conditions

    @Test("a request that fails at any level hides the title")
    func requestFailureHides() {
        // A server that is not running is this, and it is the transport's own
        // wording rather than anything the shell decided.
        #expect(
            title(transportFailure: "The server is not responding. [NSURLErrorDomain -1003]")
                == .hide(
                    .requestFailed("The server is not responding. [NSURLErrorDomain -1003]")
                )
        )
        #expect(
            title(transportFailure: "Connection refused. [NSURLErrorDomain -1004]")
                == .hide(
                    .requestFailed("Connection refused. [NSURLErrorDomain -1004]")
                )
        )
        // A timeout, which is the one that would otherwise wedge the poll.
        #expect(
            title(transportFailure: "The request timed out. [NSURLErrorDomain -1001]")
                == .hide(
                    .requestFailed("The request timed out. [NSURLErrorDomain -1001]")
                )
        )
        // No error and no response: nothing to show, and no cause to name.
        #expect(title(nil, status: nil) == .hide(.requestFailed("no response")))
        // Statuses that are not 2xx, including the 400 the range validation
        // returns and the 500 a broken server would.
        for status in [301, 400, 401, 404, 429, 500, 502, 503] {
            #expect(
                title(#"{"degraded":false,"costText":"$7.56"}"#, status: status)
                    == .hide(.requestFailed("status \(status)")),
                "status \(status)"
            )
        }
        // A body that is perfectly good still cannot be shown on a failed
        // request, which is the rule that a status check has to come first.
        #expect(title(#"{"degraded":true}"#, status: 503) == .hide(.requestFailed("status 503")))
    }

    @Test("a degraded response hides the title, because costText is absent on that arm")
    func degradedHides() {
        // The shape the server sends when its upstream stats call failed.
        #expect(title(#"{"degraded":true,"reason":"opencode is not answering"}"#) == .hide(.degraded))
        #expect(title(#"{"degraded":true,"data":{},"costText":null}"#) == .hide(.degraded))
        // Belt and braces: a body carrying both is not one the server sends, and
        // hiding is the answer that cannot be wrong.
        #expect(title(#"{"degraded":true,"costText":"$7.56"}"#) == .hide(.degraded))
    }

    @Test("a missing, null or blank costText hides the title")
    func missingCostTextHides() {
        for body in [
            #"{"degraded":false}"#,
            #"{"degraded":false,"costText":null}"#,
            #"{"degraded":false,"costText":""}"#,
            #"{"degraded":false,"costText":" "}"#,
            #"{"degraded":false,"costText":"   "}"#,
            #"{"degraded":false,"costText":"\t\n"}"#,
        ] {
            #expect(title(body) == .hide(.missingCostText), "body \(body)")
        }
    }

    /// The one condition with two names, so both are in the log and both hide:
    /// "the server is not running" is a request that failed at the transport,
    /// which is what the transport says about a server that is not there.
    @Test("a server that is not running is a request failure, and it says so")
    func serverDownHides() {
        let down = MoneyFigure.title(
            body: nil,
            statusCode: nil,
            transportFailure: "Could not connect to the server. [NSURLErrorDomain -1004]"
        )
        #expect(down == .hide(.requestFailed("Could not connect to the server. [NSURLErrorDomain -1004]")))
        // And the log line for it is findable, which is the difference between a
        // blank menu bar and a blank menu bar with an explanation.
        guard case .hide(let reason) = down else {
            Issue.record("a server that is down must hide")
            return
        }
        #expect(reason.logText == "request failed: Could not connect to the server. [NSURLErrorDomain -1004]")
    }

    /// A body the shell cannot read is treated exactly like a request that
    /// failed. A crash here would take the status item with it, and a menu bar
    /// app that dies because a server sent HTML would be a worse outcome than
    /// a missing figure.
    @Test("a malformed body hides rather than crashing, whatever shape it is")
    func malformedBodyHides() {
        for body in [
            "",
            "not json at all",
            "<html>502 Bad Gateway</html>",
            "[]",
            "[1,2,3]",
            "\"$7.56\"",
            "null",
            "{}",
            #"{"error":"range must be one of \"today\", \"7d\", \"30d\", \"all\""}"#,
            // `costText` as a number, which is what a server that had not
            // learned the contract would send.
            #"{"degraded":false,"costText":7.56}"#,
            // `degraded` missing, so there is no way to know which arm this is.
            #"{"costText":"$7.56"}"#,
        ] {
            guard case .hide(.malformedBody) = title(body) else {
                Issue.record("body \(body) must not decode into a title")
                continue
            }
        }
    }

    // MARK: - One request at a time

    @Test("the gate admits one tick and drops every tick after it until it is released")
    func gateAdmitsOne() {
        let gate = MoneyFetchGate()
        #expect(!gate.inFlight)
        #expect(gate.begin())
        #expect(gate.inFlight)
        // Three more ticks, none of which may start anything.
        #expect(!gate.begin())
        #expect(!gate.begin())
        #expect(!gate.begin())
        #expect(gate.admittedTicks == 1)
        #expect(gate.skippedTicks == 3)
        // A release is what admits the next one, and a release with nothing in
        // flight is harmless rather than a trap.
        gate.finish()
        #expect(!gate.inFlight)
        gate.finish()
        #expect(gate.begin())
        #expect(gate.admittedTicks == 2)
        #expect(gate.skippedTicks == 3)
    }

    // MARK: - The real tick

    /// A delegate whose fetch never answers, which is what a hung server looks
    /// like from here, and the three ticks that follow it.
    @MainActor
    private func delegateThatNeverAnswers(server: String = "http://127.0.0.1:4046/widget")
        -> (AppDelegate, () -> [URL], () -> Void)
    {
        let delegate = AppDelegate()
        delegate.moneyServerURL = { URL(string: server) }
        var requested: [URL] = []
        var answer: ((MoneyFigure.Title) -> Void)?
        delegate.moneyFetch = { url, done in
            requested.append(url)
            answer = done
        }
        return (delegate, { requested }, { answer?(.hide(.requestFailed("never answered"))) })
    }

    /// The no-overlap rule, proven on the tick the app runs and not on a copy of
    /// it. Three ticks against a server that never answers produce one request.
    @Test("a tick during an in-flight request is skipped rather than queued")
    @MainActor
    func tickDoesNotOverlap() {
        let (delegate, requested, neverAnswers) = delegateThatNeverAnswers()
        delegate.moneyTick()
        delegate.moneyTick()
        delegate.moneyTick()
        #expect(requested().count == 1)
        #expect(delegate.moneyAdmittedTicks == 1)
        #expect(delegate.moneyTicksSkipped == 2)
        // And nothing was shown in the meantime, so a hung server is a blank
        // menu bar rather than a stale one.
        #expect(delegate.moneyTitle == Config.emptyMoneyTitle)

        // The request answers, and the next tick works. This is the half that a
        // comment about "skips rather than queues" would not cover.
        neverAnswers()
        delegate.moneyTick()
        #expect(requested().count == 2)
        #expect(delegate.moneyAdmittedTicks == 2)
        #expect(delegate.moneyTicksSkipped == 2)
    }

    /// One request per tick, and no retry anywhere. Ten ticks against a server
    /// that fails immediately is ten requests. A retry loop or a backoff
    /// schedule would make it more than ten, and the counters are what say so.
    @Test("a failing request is answered once and never retried")
    @MainActor
    func noRetryLoop() {
        let delegate = AppDelegate()
        delegate.moneyServerURL = { URL(string: "http://127.0.0.1:4046/widget") }
        var requested = 0
        delegate.moneyFetch = { _, done in
            requested += 1
            done(.hide(.requestFailed("Connection refused. [NSURLErrorDomain -1004]")))
        }
        for _ in 0..<10 { delegate.moneyTick() }
        #expect(requested == 10)
        #expect(delegate.moneyTicksSkipped == 0)
        #expect(delegate.moneyTitle == Config.emptyMoneyTitle)
    }

    /// The four conditions again, this time at the button. Whatever was showing
    /// goes, so there is no stale figure, and what replaces it is nothing, so
    /// there is no placeholder.
    @Test("every hide condition leaves the title empty, and clears what was there")
    @MainActor
    func everyHideConditionClearsTheTitle() {
        let reasons: [MoneyFigure.HideReason] = [
            .requestFailed("Connection refused. [NSURLErrorDomain -1004]"),
            .malformedBody("not json at all"),
            .degraded,
            .missingCostText,
        ]
        for reason in reasons {
            let delegate = AppDelegate()
            delegate.moneyServerURL = { URL(string: "http://127.0.0.1:4046/widget") }
            var answer: ((MoneyFigure.Title) -> Void)?
            delegate.moneyFetch = { _, done in answer = done }

            delegate.moneyTick()
            answer?(.show("$1,234,567.90"))
            #expect(delegate.moneyTitle == "$1,234,567.90", "\(reason.logText)")

            delegate.moneyTick()
            answer?(.hide(reason))
            #expect(delegate.moneyTitle == Config.emptyMoneyTitle, "\(reason.logText)")
            #expect(delegate.moneyTitle.isEmpty, "\(reason.logText)")
        }
    }

    /// The value the server sent is the value the button holds, on the real tick
    /// rather than on the pure function.
    @Test("the tick shows the string the fetch handed over, with nothing done to it")
    @MainActor
    func tickShowsTheStringVerbatim() {
        let delegate = AppDelegate()
        delegate.moneyServerURL = { URL(string: "http://127.0.0.1:4046/widget") }
        var answer: ((MoneyFigure.Title) -> Void)?
        var requested: [URL] = []
        delegate.moneyFetch = { url, done in
            requested.append(url)
            answer = done
        }
        delegate.moneyTick()
        answer?(
            MoneyFigure.title(
                body: Data(#"{"degraded":false,"costText":"$1,234,567.90"}"#.utf8),
                statusCode: 200,
                transportFailure: nil
            )
        )
        #expect(delegate.moneyTitle == "$1,234,567.90")
        // The same tick asked the same server the panel would have.
        #expect(requested.map(\.absoluteString) == ["http://127.0.0.1:4046/api/summary?range=today&context=none"])
    }

    /// No server to ask means no request at all, and a tick that was admitted
    /// with nothing to do is released rather than left holding the gate.
    @Test("no server to ask makes no request, and does not wedge the next tick")
    @MainActor
    func noServerMakesNoRequest() {
        let delegate = AppDelegate()
        delegate.moneyServerURL = { nil }
        var requested = 0
        delegate.moneyFetch = { _, _ in requested += 1 }
        delegate.moneyTick()
        delegate.moneyTick()
        #expect(requested == 0)
        #expect(delegate.moneyTitle == Config.emptyMoneyTitle)
        #expect(delegate.moneyAdmittedTicks == 2)
        #expect(delegate.moneyTicksSkipped == 0)
    }

    /// The poll's own knobs, because a 30 second figure on some other interval
    /// is a decision nobody recorded.
    @Test("the poll is 30 seconds with a bounded request, and the empty title is empty")
    func pollKnobs() {
        #expect(Config.moneyPollInterval == 30)
        // Below the interval, so a timed-out request has released the gate by the
        // time the next tick fires rather than being skipped by it.
        #expect(Config.moneyRequestTimeout < Config.moneyPollInterval)
        #expect(Config.moneyRequestTimeout > 0)
        #expect(Config.emptyMoneyTitle == "")
        #expect(Config.moneyRequestTimeout == 10)
    }

    /// The one piece of AppKit this mission touches, pinned because getting it
    /// wrong does not fail a test, it fails silently: a title wider than the
    /// slot is clipped rather than wrapped, so the figure would simply not be
    /// there and the log would still say it was set.
    @Test("the status item is variable length, because a square slot clips the title")
    func statusItemIsWideEnoughForATitle() {
        #expect(Config.statusItemLength == NSStatusItem.variableLength)
        #expect(Config.statusItemLength != NSStatusItem.squareLength)
    }
}
