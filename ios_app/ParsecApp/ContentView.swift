import SwiftUI
import SwiftGodotKit

struct ContentView: View {
    @State var app = GodotApp(packFile: "Parsec.pck")

    var body: some View {
        GodotAppView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .environment(\.godotApp, app)
    }
}
