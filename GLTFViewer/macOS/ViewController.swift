
import Cocoa
import SceneKit
import GLTFKit2

class ViewController: NSViewController {
    var asset: GLTFAsset? {
        didSet {
            if let asset = asset {
                let source = GLTFSCNSceneSource(asset: asset)
                sceneView.scene = source.defaultScene
                animations = source.animations
                animations.first?.play()
                sceneView.scene?.rootNode.addChildNode(cameraNode)
                sceneView.scene?.lightingEnvironment.contents = "studio.hdr"
                sceneView.scene?.lightingEnvironment.intensity = 1.5
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

        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = NSColor(white: 0.18, alpha: 1.0)
        sceneView.pointOfView = cameraNode
    }
}

