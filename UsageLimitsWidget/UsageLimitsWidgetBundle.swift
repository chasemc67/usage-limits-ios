import SwiftUI
import WidgetKit

@main
struct UsageLimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageOverviewWidget()
        UsageProviderWidget()
        UsageLimitsWidget()
    }
}

/// Lock Screen. Keeps the original kind and intent so existing Lock Screen placements keep their settings.
struct UsageLimitsWidget: Widget {
    let kind = "UsageLimitsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: UsageConfigurationIntent.self, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Token Maxx")
        .description("One usage limit and when it resets. Choose the service and window.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

/// Small Home Screen: one provider.
struct UsageProviderWidget: Widget {
    let kind = "UsageProviderWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProviderConfigurationIntent.self, provider: ProviderUsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Token Maxx Provider")
        .description("Every usage limit for one provider. Choose the provider.")
        .supportedFamilies([.systemSmall])
    }
}

/// Medium and large Home Screen: every provider, nothing to configure.
struct UsageOverviewWidget: Widget {
    let kind = "UsageOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OverviewUsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Token Maxx Overview")
        .description("Usage limits for all your AI providers and when they reset.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
