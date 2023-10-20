
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
    enum GLTFDocumentSaveError : Error {
        case noAssetToWrite
    }

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
