import Foundation
import os

/// Two sinks on purpose: the unified log is what shows up in Console.app when
/// the bundle is launched from Finder, stderr is what the launch test reads.
enum Log {
    private static let logger = Logger(subsystem: "dev.joaosantos.oc-dashbar", category: "shell")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = "[oc-dashbar] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Several lines, each one a whole line. For text this shell did not write,
    /// such as the words a failed start printed, so a quoted explanation keeps
    /// the prefix on every line and `grep oc-dashbar` still finds the whole
    /// thing.
    static func info(_ messages: [String]) {
        for message in messages { info(message) }
    }
}
