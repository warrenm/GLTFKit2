
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
    }
}

