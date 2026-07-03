import SwiftUI
import SwiftGodotKit

struct ContentView: View {
    @State var app = GodotApp(packFile: "Parsec.pck")

    var body: some View {
        GodotAppView()
            .environment(\.godotApp, app)
            .ignoresSafeArea()
    }
}
