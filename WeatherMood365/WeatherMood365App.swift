import SwiftUI

@main
struct WeatherMood365App: App {
    @StateObject private var store = EntryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
