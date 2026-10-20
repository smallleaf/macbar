import Foundation
import os

/// Thin wrapper around `os.Logger`.
///
/// Per the project logging rules every diagnostic message is emitted at
/// `warning` level, uses English text, and avoids Chinese punctuation. `info`
/// output is gated to development builds.
public enum MacBarLog {
    public static let subsystem = "com.miyuan.macbar"

    public static func logger(_ category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static func warning(_ category: LogCategory, _ message: String) {
        logger(category).warning("\(message, privacy: .public)")
    }

    public static func info(_ category: LogCategory, _ message: String) {
        #if DEBUG
        logger(category).info("\(message, privacy: .public)")
        #endif
    }

    public static func error(_ category: LogCategory, _ message: String) {
        logger(category).error("\(message, privacy: .public)")
    }

    /// Replaces non-ASCII characters so log lines stay parseable and never
    /// contain the punctuation prohibited by the project rules.
    public static func sanitize(_ value: String) -> String {
        String(value.map { $0.isASCII ? $0 : "_" })
    }
}
