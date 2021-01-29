#  GLTFKit2

GLTFKit2 ~is~ will be an efficient glTF loader and exporter for Objective-C and Swift.

This project is a spiritual successor of the GLTFKit project, with many of the same aims, but some notable differences:

 - includes import and export, while GLTFKit was read-only.
 - strives to be as interoperable as possible, with extensions for Model I/O, SceneKit, and QuickLook. 
 - tries hard to retain all of the information from the asset file, meaning extensions and extras are available to client code even if they are unrecognized by the loader.
 - uses cgltf internally to load the JSON portion of glTF files. Since there are no intermediate `NSObject`s created during the parsing process, it's more efficient than GLTFKit's parser based on `NSJSONSerialization`.

This thing is just getting started. If you're reading this, you're here before the first public mention, so congratulations for being a trailblazer!
