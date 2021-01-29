
import Cocoa
import GLTFKit2

class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let assetURL = URL(fileURLWithPath: "/Users/warrenm/Downloads/glTF/busterDrone/busterDrone.gltf")
        let _ = try? GLTFAsset(url: assetURL, options: [:])
    }

}

