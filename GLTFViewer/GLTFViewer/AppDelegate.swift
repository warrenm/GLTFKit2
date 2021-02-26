
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
}
