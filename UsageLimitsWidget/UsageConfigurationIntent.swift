import AppIntents
import WidgetKit

enum ServiceChoice: String, AppEnum, CaseIterable {
    case mostConstrained
    case cursor
    case grokBot
    case codex
    case claude

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Service"

    static var caseDisplayRepresentations: [ServiceChoice: DisplayRepresentation] = [
        .mostConstrained: "Most constrained",
        .cursor: "Cursor",
        .grokBot: "Grok Bot",
        .codex: "Codex",
        .claude: "Claude",
    ]

    var kind: ServiceKind? {
        switch self {
        case .mostConstrained: return nil
        case .cursor: return .cursor
        case .grokBot: return .grokBot
        case .codex: return .codex
        case .claude: return .claude
        }
    }
}

/// The single provider shown by the small Home Screen widget.
enum ProviderChoice: String, AppEnum, CaseIterable {
    case claude
    case cursor
    case grokBot
    case codex

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"

    static var caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .claude: "Claude",
        .cursor: "Cursor",
        .grokBot: "Grok Bot",
        .codex: "Codex",
    ]

    var kind: ServiceKind {
        switch self {
        case .claude: return .claude
        case .cursor: return .cursor
        case .grokBot: return .grokBot
        case .codex: return .codex
        }
    }
}

enum WindowChoice: String, AppEnum, CaseIterable {
    case mostConstrained
    case shortest
    case longest

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Window"

    static var caseDisplayRepresentations: [WindowChoice: DisplayRepresentation] = [
        .mostConstrained: "Most constrained",
        .shortest: "Shortest (e.g. 5-hour)",
        .longest: "Longest (e.g. weekly)",
    ]
}

struct UsageConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Limit"
    static var description = IntentDescription("Choose which service and limit window to show.")

    /// Small widgets pick one provider; the Lock Screen families pick a service and window.
    /// Medium and large always show every provider.
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemSmall) {
            Summary("Show \(\.$provider)")
        } otherwise: {
            Summary("Show \(\.$service) \(\.$window)")
        }
    }

    /// Used by the small Home Screen widget.
    @Parameter(title: "Provider", default: .claude)
    var provider: ProviderChoice

    @Parameter(title: "Service", default: .mostConstrained)
    var service: ServiceChoice

    @Parameter(title: "Window", default: .mostConstrained)
    var window: WindowChoice

    init() {}

    init(service: ServiceChoice, window: WindowChoice) {
        self.service = service
        self.window = window
    }

    init(provider: ProviderChoice) {
        self.provider = provider
    }
}
