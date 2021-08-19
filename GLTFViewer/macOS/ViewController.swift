
import Cocoa
import SceneKit
import GLTFKit2

class ViewController: NSViewController {

    var scnView: SCNView {
        return self.view as! SCNView
    }
    
    var scene: SCNScene? {
        didSet {
            scnView.scene = scene
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        
        let pointOfView = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 120.0
        pointOfView.camera = camera
        scnView.pointOfView = pointOfView
    }
}

