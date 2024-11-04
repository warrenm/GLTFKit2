
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

class GLTFDocument: NSDocument, NSOpenSavePanelDelegate {
    enum GLTFDocumentSaveError : Error {
        case noAssetToWrite
    }

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

    var asset: GLTFAsset? = GLTFAsset() {
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
    
    var currentDestinationURL: URL?

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       delegate: Any?, didSave didSaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?)
    {
        currentDestinationURL = url
        super.save(to: url, ofType: typeName, for: saveOperation, delegate: delegate, 
                   didSave: didSaveSelector, contextInfo: contextInfo)
        currentDestinationURL = nil
    }

    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL absoluteOriginalContentsURL: URL?) throws
    {
        guard let asset = asset else {
            throw GLTFDocumentSaveError.noAssetToWrite
        }

        var writeOptions: [GLTFAssetExportOption : Any] = [:]
        if url.isFileURL && url.pathExtension == "glb" {
            writeOptions[.asBinary] = true
        }

        let buffersToWrite = asset.buffers.filter { return ($0.uri != nil) && $0.uri!.isFileURL }
        let imagesToWrite = asset.images.filter { return ($0.uri != nil) && $0.uri!.isFileURL }

        try asset.write(to: url, options: writeOptions)

        if let destinationURL = currentDestinationURL {
            let baseURL = destinationURL.deletingLastPathComponent()
            for buffer in buffersToWrite {
                if let uri = buffer.uri, let data = buffer.data {
                    let destinationURL = baseURL.appendingPathComponent(uri.relativePath, isDirectory: false)
                    try data.write(to: destinationURL, options: [])
                }
            }
            for image in imagesToWrite {
                if let uri = image.uri, let data = image.representation {
                    let destinationURL = baseURL.appendingPathComponent(uri.relativePath, isDirectory: false)
                    try data.write(to: destinationURL, options: [])
                }
            }
        }
    }
}
