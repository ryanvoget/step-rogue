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

// UIViewControllerRepresentable ensures UIKit — not SwiftUI layout — owns the
// view frame.  UIKit sets the root view frame to {0,0,screenW,screenH}, so
// UIGodotAppView.layer.frame always has origin (0,0) and the touch coordinate
// check inside SwiftGodotKit never filters out valid taps.
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
        // UIGodotAppView.init(frame:) is internal to SwiftGodotKit; the
        // compiler exposes only the inherited NSObject.init() (no args).
        // At runtime ObjC dispatch calls init(frame:.zero) correctly.
        let gv = UIGodotAppView()
        gv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gv.contentScaleFactor = UIScreen.main.scale
        gv.isMultipleTouchEnabled = true
        godotApp.configureLaunch(source: nil, scene: nil)
        godotApp.start()
        gv.app = godotApp
        view = gv
    }
}
