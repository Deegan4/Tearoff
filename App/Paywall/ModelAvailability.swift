import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether this device can actually run on-device receipt extraction. The
/// paywall must branch on this: advertising AI extraction to an ineligible
/// device produces refunds and a plausible App Review §3.1.2 problem (spec §7).
enum ModelAvailability {
    case available
    case unavailable

    static var current: ModelAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        default: return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    var canExtract: Bool { self == .available }
}
