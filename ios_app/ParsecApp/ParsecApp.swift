import SwiftUI
import SwiftGodot
import SwiftGodotKit

@main
struct ParsecApp: App {
    init() {
        let previous = initHookCb
        initHookCb = { level in
            previous?(level)
            if level == .scene {
                register(type: HealthKitBridge.self)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
