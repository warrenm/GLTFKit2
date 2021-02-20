
import Cocoa
import SceneKit
import GLTFKit2

class ViewController: NSViewController {

    var scnView: SCNView {
        return self.view as! SCNView
    }

    var asset: GLTFAsset! {
        didSet {
            scnView.scene = SCNScene(gltfAsset:asset)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
    }
}

