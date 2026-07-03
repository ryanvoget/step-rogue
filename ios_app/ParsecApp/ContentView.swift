import SwiftUI
import SwiftGodotKit
import UIKit

struct ContentView: View {
    @State var app = GodotApp(packFile: "Parsec.pck")

    var body: some View {
        GodotViewControllerWrapper(app: app)
            .ignoresSafeArea(.all)
    }
}

private struct GodotViewControllerWrapper: UIViewControllerRepresentable {
    let app: GodotApp

    func makeUIViewController(context: Context) -> GodotViewController {
        GodotViewController(app: app)
    }

    func updateUIViewController(_ vc: GodotViewController, context: Context) {}
}

private final class GodotViewController: UIViewController {
    let godotApp: GodotApp

    init(app: GodotApp) {
        self.godotApp = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let gv = UIGodotAppView(frame: UIScreen.main.bounds)
        gv.contentScaleFactor = UIScreen.main.scale
        gv.isMultipleTouchEnabled = true
        godotApp.configureLaunch(source: nil, scene: nil)
        godotApp.start()
        gv.app = godotApp
        view = gv
    }
}
