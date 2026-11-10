import Foundation
import Observation
import IKCEFBridge

/// Chromium owns and persists these per-Space settings; SwiftUI observes that same source.
@MainActor @Observable
final class CEFNativePreferences {
    static let shared = CEFNativePreferences()
    private(set) var revision = 0
    private init() {
        IKCEFSecurity.setChangeHandler { [weak self] _ in
            MainActor.assumeIsolated { self?.revision &+= 1 }
        }
    }
}
