#  GLTFKit2

GLTFKit2 ~is~ will be an efficient glTF loader and exporter for Objective-C and Swift.

This project is a spiritual successor of the [GLTFKit](https://github.com/warrenm/GLTFKit) project, with many of the same aims, but some notable differences. GLTFKit2:

 - includes import and export, while GLTFKit was read-only.
 - strives to be as interoperable as possible, with extensions for Model I/O, SceneKit, and QuickLook. 
 - tries to retain all of the information from the asset file, meaning extensions and extras are available to client code even if they are unrecognized by the loader.
 - uses cgltf and JSMN internally to load the JSON portion of glTF files, which is more efficient than parsing with `NSJSONSerialization`.

This thing is just getting started. Expect it not to be production-ready for many months.
