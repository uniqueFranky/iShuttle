import SwiftUI

@main
struct iShuttleApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
