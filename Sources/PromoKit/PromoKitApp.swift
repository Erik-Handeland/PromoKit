import SwiftUI

@main
struct PromoKitApp: App {
    @State private var store = CodeStore()
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(
                    AppAppearance(rawValue: appAppearanceRawValue)?.colorScheme
                )
        }
    }
}
