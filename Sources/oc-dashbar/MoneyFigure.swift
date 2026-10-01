import Foundation

/// What the menu bar shows for today's spend, and the reasons it is not showing
/// anything when it is not showing anything.
///
/// The string in `.show` is the server's `costText`, byte for byte. It is never
/// parsed, reformatted, or compared to zero, and nothing in this file could do
/// any of those things to it. That is the Captain's ruling and the reason is in
/// the project: `Intl.NumberFormat` rounds ties away from zero and neither
/// `String(format:)` nor `NumberFormatter` reproduces it, so a formatter on this
/// side would be a correctness risk dressed as a tidy-up. The server sends the
/// finished string and this shell hands it to the button unchanged.
///
/// That also means there is no branch for an unpriced model and no branch for an
/// empty day. Both arrive as `"$0.00"` and both display as `"$0.00"`, which is
/// what the Captain chose over special casing.
enum MoneyFigure {
    /// The title for the status item, or the reason there is none.
    enum Title: Equatable {
        /// `costText` exactly as the server wrote it.
        case show(String)
        /// Nothing. No placeholder, no dash, no zero, no last known value.
        case hide(HideReason)
    }

    /// The four things that can mean "no figure", kept apart because a menu bar
    /// that is silently blank is indistinguishable from a bug and the log has to
    /// be able to tell them apart.
    enum HideReason: Equatable {
        /// The request failed at any level. A server that is not running is this
        /// case and not one of its own: the transport reports connection refused
        /// and there is no response to inspect, which is the same answer.
        case requestFailed(String)
        /// A response whose body is not the contract. A body the shell cannot
        /// read is treated exactly like a request that failed, because both end
        /// with nothing to show and neither is worth a crash.
        case malformedBody(String)
        /// The server answered `degraded: true`, and `costText` is absent on that
        /// arm, so there is nothing to show.
        case degraded
        /// `costText` was null, absent, or blank.
        case missingCostText

        /// The reason in words, for the log.
        var logText: String {
            switch self {
            case .requestFailed(let detail): return "request failed: \(detail)"
            case .malformedBody(let detail): return "the body was not the summary contract: \(detail)"
            case .degraded: return "the server answered degraded, and costText is absent on that arm"
            case .missingCostText: return "costText was missing, null or blank"
            }
        }
    }

    /// The title a finished request produced, from whatever it produced.
    ///
    /// Pure, so every hide condition and every way of failing to parse is
    /// reachable from a test without a server and without a network. The order is
    /// the order of what went wrong rather than the order of convenience: a
    /// transport failure beats a status code, and a status code beats a body.
    ///
    /// `transportFailure` is the description URLSession reported, and nil when it
    /// reported nothing. A `String` rather than an `Error` so this stays a
    /// function of values a test can write down, and so the reason that reaches
    /// the log is the reason rather than a re-derivation of one.
    static func title(body: Data?, statusCode: Int?, transportFailure: String?) -> Title {
        if let transportFailure {
            return .hide(.requestFailed(transportFailure))
        }
        guard let statusCode else {
            // No error and no response is not a shape URLSession produces, but
            // there is nothing to show either, and naming a cause for a shape we
            // have never seen would be a worse answer than the one that hides.
            return .hide(.requestFailed("no response"))
        }
        guard (200...299).contains(statusCode) else {
            return .hide(.requestFailed("status \(statusCode)"))
        }
        guard let body else {
            return .hide(.malformedBody("an empty body with a success status"))
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: body)
        }
        catch {
            // Includes a body that is a JSON array, a JSON string, the error arm
            // the range validation returns, and a `costText` that arrived as a
            // number. All of them are a body that is not this contract.
            return .hide(.malformedBody("\(error)"))
        }
        guard !envelope.degraded else { return .hide(.degraded) }
        guard let text = envelope.costText,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .hide(.missingCostText) }
        // The original string, not the trimmed one. The trim above only decides
        // whether there is anything to show at all; a value with a trailing zero
        // and seven figures comes back exactly as it arrived.
        return .show(text)
    }

    /// The whole of the contract this shell reads, and nothing else.
    ///
    /// `costText` is optional because the server omits it on the degraded arm,
    /// which is the documented reason it is missing rather than an accident.
    /// `degraded` is not optional, because every non-degraded body carries it and
    /// a body without it is not this contract.
    ///
    /// `data` is absent on purpose. It is the opencode service's payload spread
    /// through untouched, and nothing in it is read, so nothing in it can drift
    /// out from under the figure.
    private struct Envelope: Decodable {
        let degraded: Bool
        let costText: String?
    }
}

/// One request at a time, ever.
///
/// The rule exists because a slow or hung server is not a reason to build a
/// backlog. A tick that arrives while a request is in flight is skipped, not
/// queued, so the worst case is one live request rather than a growing pile of
/// them. There is no retry loop, no backoff schedule and no error cascade
/// anywhere that could produce one: a tick either starts the one request it is
/// allowed or it does nothing.
///
/// Read and written only on the main thread. A tick is a timer fire on the main
/// run loop and a completion is hopped to the main queue before it calls
/// `finish()`, so the counters below have exactly one writer and no lock.
final class MoneyFetchGate {
    private(set) var inFlight = false
    /// Ticks allowed to make a request, and ticks dropped because one was
    /// already in flight. Both are in the log, so "the figure stopped changing"
    /// and "the figure never arrived" are two different lines rather than one
    /// silence. The first counts admissions and not requests, because a tick
    /// admitted with no server to ask is still an admitted tick.
    private(set) var admittedTicks = 0
    private(set) var skippedTicks = 0

    /// Whether this tick may start a request. False means skip, which is the
    /// whole of the no-overlap rule.
    func begin() -> Bool {
        guard !inFlight else {
            skippedTicks += 1
            return false
        }
        inFlight = true
        admittedTicks += 1
        return true
    }

    /// Releases the gate. Called exactly once for every request `begin()`
    /// admitted, whatever the outcome was, so a failure cannot wedge the poll.
    func finish() {
        inFlight = false
    }
}
