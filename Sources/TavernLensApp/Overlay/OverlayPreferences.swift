import Foundation
import Observation
import OverlayLayout

/// Overlay presentation preferences shared by the running overlay and Settings.
/// Changes take effect immediately and are remembered across launches.
@MainActor
@Observable
final class OverlayPreferences {
    private enum Key {
        static let density = "overlayDensity"
        static let advisor = "overlayShowsAdvisor"
        static let buildGuidance = "overlayShowsBuildGuidance"
        static let opponentScouting = "overlayShowsOpponentScouting"
    }

    var density: OverlayDensity {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }

    var showsAdvisor: Bool {
        didSet { defaults.set(showsAdvisor, forKey: Key.advisor) }
    }

    var showsBuildGuidance: Bool {
        didSet { defaults.set(showsBuildGuidance, forKey: Key.buildGuidance) }
    }

    var showsOpponentScouting: Bool {
        didSet { defaults.set(showsOpponentScouting, forKey: Key.opponentScouting) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        density = defaults.string(forKey: Key.density).flatMap(OverlayDensity.init(rawValue:)) ?? .compact
        showsAdvisor = Self.visibility(forKey: Key.advisor, defaults: defaults)
        showsBuildGuidance = Self.visibility(forKey: Key.buildGuidance, defaults: defaults)
        showsOpponentScouting = Self.visibility(forKey: Key.opponentScouting, defaults: defaults)
    }

    func resetToDefaults() {
        density = .compact
        showsAdvisor = true
        showsBuildGuidance = true
        showsOpponentScouting = true
    }

    private static func visibility(forKey key: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
