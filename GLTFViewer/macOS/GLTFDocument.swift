import Cocoa
import GLTFKit2

class GLTFDocument: NSDocument, NSOpenSavePanelDelegate {

    enum DocumentState {
        case uninitialized
        case opening
        case requestingPermissions
        case opened
        case failed
        case closed
    }
    public private(set) var state = DocumentState.uninitialized

    private var parentDirectoryURL: URL?

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

    override class var autosavesInPlace: Bool {
        return false
    }

    private var reopenAttempts = 0
    override func read(from url: URL, ofType typeName: String) throws {
        state = .opening
        
        var options = [GLTFAssetLoadingOption : Any]()
        if let assetDirectoryURL = parentDirectoryURL {
            options[.assetDirectoryURLKey] = assetDirectoryURL
        }

        GLTFAsset.load(with: url, options: options) { (progress, status, maybeAsset, maybeError, _) in
            DispatchQueue.main.async {
                if status == .complete {
                    self.state = .opened
                    self.asset = maybeAsset
                } else if let error = maybeError {
                    if (error as NSError).code == GLTFErrorCodeIOError && self.reopenAttempts == 0 {
                        self.reopenAttempts += 1
                        DispatchQueue.main.async {
                            try? self.requestPermissionsAndRetryOpen(for: url.deletingLastPathComponent(), assetURL: url)
                        }
                    } else {
                        self.state = .failed

                        // Close the document window we created to display this asset and show an error dialog instead
                        self.closeAllWindows()
                        NSAlert(error: error).runModal()
                    }
                }
            }
        }
    }

    private func closeAllWindows() {
        self.windowControllers.forEach {
            windowController in windowController.close()
        }
    }

    private func requestPermissionsAndRetryOpen(for requestedURL: URL, assetURL: URL) throws {
        self.state = .requestingPermissions
        let openPanel = NSOpenPanel()
        openPanel.message = "glTF Viewer needs access to the directory containing this asset so it can open any files it references. Please click Open."
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.delegate = self
        let result = openPanel.runModal()
        if result == .OK {
            if let grantedURL = openPanel.url {
                self.parentDirectoryURL = grantedURL
                try self.read(from: assetURL, ofType: "")
            }
        } else {
            self.closeAllWindows()
        }
    }
}
