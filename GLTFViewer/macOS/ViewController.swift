
import Cocoa
import SceneKit
import GLTFKit2

class ViewController: NSViewController {

    var scnView: SCNView {
        return self.view as! SCNView
    }
    
    var asset: GLTFAsset? {
        didSet {
            if let asset = asset {
                let source = GLTFSCNSceneSource(asset: asset)
                scnView.scene = source.defaultScene
                animations = source.animations
                if let defaultAnimation = animations.first {
                    for channel in defaultAnimation.channels {
                        channel.target.addAnimation(channel.animation, forKey: nil)
                    }
                }
                scnView.scene?.lightingEnvironment.contents = "Backgrounds/studio007.hdr"
                scnView.scene?.background.contents = NSColor(white: 0.18, alpha: 1.0)
            }
        }
    }

    var animations = [GLTFSCNAnimation]()

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

