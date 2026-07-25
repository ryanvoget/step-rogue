import SwiftUI
import SwiftGodot
import SwiftGodotKit
import UIKit

// Orientation is driven by the Godot game (SaveManager.target_orientation, polled in
// ContentView.swift): menus are portrait, the game is landscape. iOS asks the app delegate for
// the window's allowed orientations, so routing it through here (rather than a child view
// controller, which SwiftUI's hosting controller would override) is what actually makes the
// device rotate. AppOrientation.mask is flipped at runtime, then a geometry update forces it.
enum AppOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppOrientation.mask
    }
}

@main
struct ParsecApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let previous = initHookCb
        initHookCb = { level in
            previous?(level)
            if level == .scene {
                print("[ParsecApp] registering HealthKitBridge at .scene level")
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
