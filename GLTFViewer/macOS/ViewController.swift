
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
                sceneView.pointOfView?.light = cameraLight

                if asset.animations.count > 0 {
                    if animationController == nil {
                        showAnimationUI()
                        animationController.sceneView = sceneView
                    }
                    animationController.animations = source.animations
                }
            }
        }
    }

    private var sceneView: SCNView {
        return view as! SCNView
    }

    private var animationController: AnimationPlaybackViewController!

    private var animations = [GLTFSCNAnimation]()

    @IBOutlet weak var focusOnSceneMenuItem: NSMenuItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = NSColor(named: "BackgroundColor") ?? NSColor.white
        sceneView.antialiasingMode = .multisampling4X
    }

    @IBAction func focusOnScene(_ sender: Any) {
        if let (sceneCenter, sceneRadius) = sceneView.scene?.rootNode.boundingSphere,
            let pointOfView = sceneView.pointOfView
        {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.750
            if let camera = pointOfView.camera {
                camera.automaticallyAdjustsZRange = true
                camera.fieldOfView = 60.0
            }
            let simdCenter = simd_float3(Float(sceneCenter.x), Float(sceneCenter.y), Float(sceneCenter.z))
            pointOfView.simdPosition = sceneRadius * SIMD3<Float>(1, 0.5, 1) + simdCenter
            pointOfView.look(at: sceneCenter, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.commit()
        }
    }

    private func showAnimationUI() {
        animationController = AnimationPlaybackViewController(nibName: "AnimationPlaybackView", bundle: nil)
        animationController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationController.view)
        let views = [ "controller" : animationController.view ]
        NSLayoutConstraint(item: animationController.view, attribute:.width, relatedBy:.equal,
                           toItem: nil, attribute: .notAnAttribute, multiplier:0, constant:480).isActive = true
        NSLayoutConstraint(item: animationController.view, attribute:.height, relatedBy:.equal,
                           toItem: nil, attribute:.notAnAttribute, multiplier:0, constant:100).isActive = true
        NSLayoutConstraint(item:animationController.view, attribute:.centerX, relatedBy:.equal,
                           toItem: view, attribute: .centerX, multiplier:1, constant:0).isActive = true
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[controller]-(12)-|",
                                                           options: [],
                                                           metrics:nil,
                                                           views:views))
    }
}

