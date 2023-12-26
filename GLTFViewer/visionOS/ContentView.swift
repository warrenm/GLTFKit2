import SwiftUI
import RealityKit
import GLTFKit2

struct ContentView: View {
    var body: some View {
        GeometryReader3D { geometry in
            RealityView(make: { content in
                let assetURL = Bundle.main.url(forResource: "DamagedHelmet",
                                               withExtension: "glb",
                                               subdirectory: "Models")!
                async let rootEntity = GLTFRealityKitLoader.load(from: assetURL)

                if let entity = try? await rootEntity {
                    let contentBounds = content.convert(geometry.frame(in: .local),
                                                        from: .local, to: content)
                    let contentExtent = contentBounds.extents.min()
                
                    let entityBounds = entity.visualBounds(relativeTo: nil)
                    let entityExtent = entityBounds.extents.max()
                    let entityCenter = entityBounds.center
                    let scaleFactor = 0.9 * (contentExtent / entityExtent)
                    entity.scale = [scaleFactor, scaleFactor, scaleFactor]
                    entity.position = -entityCenter * scaleFactor
                    
                    content.add(entity)
                }
            }, placeholder: {
                ProgressView()
            })
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
}
