import Foundation

/// App-group identifiers shared by the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.AnomalousResearch.UsageLimits"

    /// Shared UserDefaults. Falls back to `.standard` if the app group is unavailable
    /// (e.g. unsigned simulator builds) so the app keeps working, just without widget sharing.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
