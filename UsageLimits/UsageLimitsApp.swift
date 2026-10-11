import SwiftUI

@main
struct UsageLimitsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(TMX.orange)
        }
    }
}
