#if DEBUG
import Foundation

enum DebugEnvironment {
    static func value(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }
}
#endif
