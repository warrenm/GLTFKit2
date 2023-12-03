
import SwiftUI

@main
struct GLTFViewerApp: App {
    var body: some Scene {
        WindowGroup(id: "3D Model") {
            ContentView()
        }
        .windowStyle(.volumetric)
        .defaultSize(Size3D(width: 0.8, height: 0.8, depth: 0.8), in: .meters)
    }
}
