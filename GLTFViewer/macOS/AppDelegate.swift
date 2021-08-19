
import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
    }

    func applicationWillTerminate(_ aNotification: Notification) {
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

}
