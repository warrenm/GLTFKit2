
import Cocoa
import GLTFKit2

class GLTFDocument: NSDocument {
    
    var asset: GLTFAsset? {
        didSet {
            if let asset = asset {
                DispatchQueue.main.async {
                    if let contentViewController = self.windowControllers.first?.contentViewController as? ViewController {
                        contentViewController.scene = SCNScene(gltfAsset: asset)
                    }
                }
            }
        }
    }
    
    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("GLTFWindowController"))
        self.addWindowController(windowController as! NSWindowController)
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        GLTFAsset.load(with: url, options: [:]) { (progress, status, maybeAsset, maybeError, _) in
            if status == .complete {
                self.asset = maybeAsset
            }
        }
    }
}

