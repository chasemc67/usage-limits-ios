import SwiftUI
import WidgetKit

@main
struct UsageLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageLimitsWidget()
    }
}

struct UsageLimitsWidget: Widget {
    let kind = "UsageLimitsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: UsageConfigurationIntent.self, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Token Maxx")
        .description("Your AI usage limits and when they reset.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
