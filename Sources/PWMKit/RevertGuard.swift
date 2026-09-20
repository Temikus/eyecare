import Dispatch
import Foundation

/// Holds a write for a while, then puts the old values back.
///
/// These properties are runtime-only, so a reboot always clears them, but a bad value can black
/// out the panel for the whole session. The guard restores on its timer and on SIGINT/SIGTERM, so
/// even a dark screen recovers by waiting or hitting ^C blind.
public enum RevertGuard {
    /// Splits requested keys into those that can be restored and those with no prior value.
    public static func plan(
        keys: some Collection<String>, current: [String: PropertyValue],
        overrides: [String: PropertyValue] = [:]
    ) -> (restorable: [String: PropertyValue], unpublished: [String]) {
        var restorable: [String: PropertyValue] = [:]
        var unpublished: [String] = []
        for key in keys {
            if let override = overrides[key], override.isWritable {
                restorable[key] = override
            } else if let value = current[key], value.isWritable {
                restorable[key] = value
            } else {
                unpublished.append(key)
            }
        }
        return (restorable, unpublished.sorted())
    }

    /// Counts down, then runs `restore`. Also runs it on ^C or SIGTERM and exits 130.
    public static func hold(
        seconds: Int, tick: (Int) -> Void, restore: @escaping @Sendable () -> Void
    ) {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let queue = DispatchQueue(label: "dev.temik.pwmctl.revert")
        let sources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                restore()
                exit(130)
            }
            source.resume()
            return source
        }
        defer {
            for source in sources { source.cancel() }
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }

        for remaining in stride(from: seconds, through: 1, by: -1) {
            tick(remaining)
            Thread.sleep(forTimeInterval: 1)
        }
        restore()
    }
}
