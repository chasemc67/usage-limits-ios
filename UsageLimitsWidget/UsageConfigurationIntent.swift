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

    @Parameter(title: "Service", default: .mostConstrained)
    var service: ServiceChoice

    @Parameter(title: "Window", default: .mostConstrained)
    var window: WindowChoice

    init() {}

    init(service: ServiceChoice, window: WindowChoice) {
        self.service = service
        self.window = window
    }
}
