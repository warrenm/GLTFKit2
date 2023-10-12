
import Cocoa
import GLTFKit2

class DocumentController : NSDocumentController {
    var didReopenDocument = false

    override func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool,
                                 completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void)
    {
        // Note that we reopened document(s) so we can present an Open dialog later if we didn't
        didReopenDocument = true
        super.reopenDocument(for: urlOrNil, withContentsOf: contentsURL, display: displayDocument,
                             completionHandler: completionHandler)
    }
}

class GLTFDocument: NSDocument {
    
    var asset: GLTFAsset? {
        didSet {
            if let asset = asset {
                if let contentViewController = self.windowControllers.first?.contentViewController as? ViewController {
                    contentViewController.asset = asset
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
            DispatchQueue.main.async {
                if status == .complete {
                    self.asset = maybeAsset
                } else if let error = maybeError {
                    // Close the document window we created to display this asset and show an error dialog instead
                    self.windowControllers.forEach {
                        windowController in windowController.close()
                    }
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
}
