
import UIKit
import SceneKit
import GLTFKit2

class ViewController: UIViewController {
    var asset: GLTFAsset? {
        didSet {
            if let asset = asset {
                let source = GLTFSCNSceneSource(asset: asset)
                sceneView.scene = source.defaultScene
                animations = source.animations
                if let defaultAnimation = animations.first {
                    sceneView.scene?.rootNode.addAnimationPlayer(defaultAnimation.animationPlayer, forKey: nil)
                }
                sceneView.scene?.rootNode.addChildNode(cameraNode)
            }
        }
    }

    private var sceneView: SCNView {
        return view as! SCNView
    }

    private var animations = [GLTFSCNAnimation]()

    private let camera = SCNCamera()
    private let cameraNode = SCNNode()

    override func viewDidLoad() {
        super.viewDidLoad()

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3.5)
        camera.automaticallyAdjustsZRange = true

        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.pointOfView = cameraNode

        loadAsset()
    }

    private func loadAsset() {
        guard let assetURL = Bundle.main.url(forResource: "DamagedHelmet",
                                             withExtension: "glb",
                                             subdirectory: "Models")
        else {
            print("Failed to find asset for URL")
            return
        }

        GLTFAsset.load(with: assetURL, options: [:]) { (progress, status, maybeAsset, maybeError, _) in
            DispatchQueue.main.async {
                if status == .complete {
                    self.asset = maybeAsset
                } else if let error = maybeError {
                    print("Failed to load glTF asset: \(error)")
                }
            }
        }
    }
}
