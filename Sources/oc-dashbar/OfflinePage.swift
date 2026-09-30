import Foundation

/// The page the shell shows when the dashboard is not answering.
///
/// It is generated here rather than fetched, because the state it exists for is
/// the state where nothing is serving. Beyond the words it carries three things:
///
/// - A start control that emits `Config.startURLString`, the same verb the
///   served widget's own button emits. The shell intercepts it. This page does
///   not know what happens next and does not claim to.
/// - The command line a person can run in their own terminal. That is the
///   escape hatch for the case the button cannot cover: a first `npx` run that
///   downloads the package, a machine that is offline, and any failure whose
///   output is worth reading somewhere other than a menu bar widget.
/// - The port that was tried and the registry file the shell consults, so an
///   empty panel answers "which port, which file" at a glance. Neither value
///   costs a read: the port comes from the URL that failed and the path is the
///   same one the per-open log line already names.
///
/// The wait after a click is bounded and single. One `setTimeout`, no
/// `setInterval`, and when it fires the page says it gave up and hands the
/// reader back to the two manual controls. The page cannot see whether the
/// spawn worked, so it never says that it did, and it does not poll to find
/// out. The bound is `Config.startWatchTimeout`, the same 25 seconds the shell
/// itself watches a start for, so the page stops pretending at the moment the
/// shell stops watching.
enum OfflinePage {
    /// The whole document.
    ///
    /// `tried` is the URL whose load failed, or nil when nothing resolved. It
    /// decides the retry link and the port line; the start control is on the
    /// page either way, because a dashboard that cannot be addressed is
    /// exactly what the control is for.
    ///
    /// `waitSeconds` has a default so the application never passes it and the
    /// bound stays `Config`'s. The one caller that passes it is a test, which
    /// cannot wait 25 seconds per click and drives the identical page code at a
    /// compressed bound.
    static func html(
        tried: URL?,
        registryPath: String,
        waitSeconds: Int = Int(Config.startWatchTimeout)
    ) -> String {
        let waitMilliseconds = waitSeconds * 1000
        let retry =
            tried.map { "<p class=\"retry\"><a href=\"\($0.absoluteString)\">Try again</a></p>" } ?? ""
        // The give-up line points at whatever controls this page actually
        // carries. The no-URL variant has no retry link, so telling it to
        // "Try again" would be pointing at nothing.
        let nextStep =
            tried == nil
            ? "The dashboard may still be starting. Run the command in a terminal to see what it says."
            : "The dashboard may still be starting. Try again, or run the command in a terminal to see what it says."
        return #"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <title>oc-dash</title>
            <style>
            :root { color-scheme: light dark; --dim: #555555; }
            @media (prefers-color-scheme: dark) { :root { --dim: #b4b4b4; } }
            html, body { height: 100%; margin: 0; }
            body { display: flex; align-items: center; justify-content: center; box-sizing: border-box;
                   padding: 24px; text-align: center; background: Canvas; color: CanvasText;
                   font: 13px/1.45 -apple-system, system-ui, sans-serif; }
            main { max-width: 100%; }
            h1 { font-size: 13px; font-weight: 600; margin: 0 0 14px; }
            p { margin: 0 0 12px; color: var(--dim); }
            p:last-child { margin-bottom: 0; }
            button { font: inherit; padding: 6px 16px; border-radius: 7px;
                     border: 1px solid rgba(127, 127, 127, 0.45);
                     background: rgba(127, 127, 127, 0.18); color: CanvasText; }
            button:disabled { color: var(--dim); }
            code { font: 11px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; color: CanvasText;
                   overflow-wrap: anywhere; }
            a { color: LinkText; }
            .diag { font-size: 11px; overflow-wrap: anywhere; }
            </style>
            </head>
            <body>
            <main>
            <h1>The oc-dash dashboard is not answering.</h1>
            <p id="control"><button id="start" type="button">Start the dashboard</button></p>
            <p class="command">Or run this in a terminal:<br><code>\#(StartServer.byHand)</code></p>
            <p id="status" role="status" hidden></p>
            \#(retry)
            <p class="diag">\#(escaped(portLine(of: tried)))<br>Registry: \#(escaped(registryPath))</p>
            </main>
            <script>
            (function () {
              var button = document.getElementById("start");
              var status = document.getElementById("status");
              var wait = \#(waitMilliseconds);
              var timer = 0;
              function giveUp() {
                status.textContent = "Gave up waiting after \#(waitSeconds) seconds. \#(nextStep)";
                button.disabled = false;
                button.textContent = "Start again";
              }
              button.addEventListener("click", function () {
                button.disabled = true;
                button.textContent = "Starting\u2026";
                status.hidden = false;
                status.textContent = "Starting the dashboard. The first run can take ten or twenty seconds"
                  + " while npx downloads the package.";
                window.clearTimeout(timer);
                timer = window.setTimeout(giveUp, wait);
                window.location.href = "\#(Config.startURLString)";
              });
            })();
            </script>
            </body>
            </html>
            """#
    }

    /// "Port tried: 4021", from the URL whose load failed.
    ///
    /// The registry and the built-in default always carry an explicit port;
    /// only a hand-written `OC_DASHBAR_URL` can omit one, and there the URL
    /// itself is the honest answer.
    private static func portLine(of tried: URL?) -> String {
        guard let tried else { return "Port tried: none, nothing resolved" }
        guard let port = tried.port else { return "Port tried: none in \(tried.absoluteString)" }
        return "Port tried: \(port)"
    }

    /// The three characters that could otherwise be read as markup. One pass,
    /// ampersand first, so a path that literally contains `&amp;` renders as
    /// the path it is.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
