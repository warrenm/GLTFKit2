
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
                sceneView.scene?.lightingEnvironment.intensity = 1.0

                let sunLight = SCNLight()
                sunLight.type = .directional
                sunLight.intensity = 800
                sunLight.color = NSColor.white
                sunLight.castsShadow = true
                let sun = SCNNode()
                sun.light = sunLight
                sceneView.scene?.rootNode.addChildNode(sun)
                sun.look(at: SCNVector3(-1, -1, -1))

                let moonLight = SCNLight()
                moonLight.type = .directional
                moonLight.intensity = 200
                moonLight.color = NSColor.white
                let moon = SCNNode()
                moon.light = moonLight
                sceneView.scene?.rootNode.addChildNode(moon)
                moon.look(at: SCNVector3(1, -1, -1))

                let cameraLight = SCNLight()
                cameraLight.type = .directional
                cameraLight.intensity = 500
                cameraLight.color = NSColor.white
                cameraNode.light = cameraLight
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
        sceneView.backgroundColor = NSColor(white: 0.18, alpha: 1.0)
        sceneView.pointOfView = cameraNode
    }
}

