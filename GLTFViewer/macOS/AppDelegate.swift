import Cocoa
import GLTFKit2

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Uncomment this to register the sample Draco decompressor.
        // You must also link against Draco in your target.
        //GLTFAsset.dracoDecompressorClassName = "DracoDecompressor"
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let _ = try? GLTFDocument(for: nil, withContentsOf: url, ofType: "model/gltf")
        }
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Even though we're an "editor" of glTF files, that really just means we want to be
        // able to export to other formats; you can't create a model from scratch, so opening
        // an empty document at launch doesn't make sense.
        return false
    }

    private var lastReopenRequestTime: TimeInterval = 0.0
    private let reopenRequestDebounceInterval: TimeInterval = 1.0

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let eventTime = sender.currentEvent?.timestamp {
            if eventTime < lastReopenRequestTime + reopenRequestDebounceInterval {
                return false // Debounce repeated requests
            } else {
                lastReopenRequestTime = eventTime
            }
        }
        // Upon being reopened via the dock tile, present an Open dialog if we have no documents open
        if !flag {
            NSDocumentController.shared.openDocument(self)
            return false
        }
        return true
    }
}
