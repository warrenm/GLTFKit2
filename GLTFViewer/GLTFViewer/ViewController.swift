
import Cocoa
import Metal
import MetalKit
import GLTFKit2

class ViewController: NSViewController, MTKViewDelegate {
    
    let device = MTLCreateSystemDefaultDevice()!
    var commandQueue: MTLCommandQueue!
    
    var asset: GLTFAsset! {
        didSet {
            scene = asset.defaultScene
            prepareToRender()
        }
    }
    
    private var scene: GLTFScene!
    
    private var lightNodes = [GLTFNode]()
    private var renderNodes = [GLTFNode]()
    private var buffers = [MTLBuffer]()
    private var textures = [MTLTexture]()

    var mtkView: MTKView {
        return self.view as! MTKView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        commandQueue = device.makeCommandQueue()

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.sampleCount = 4
        mtkView.delegate = self
    }
    
    private func prepareToRender() {
        buffers = []
        for buffer in asset.buffers {
            let data = buffer.data! as NSData
            let buffer = device.makeBuffer(bytes: data.bytes, length: data.length, options: [.storageModeShared])!
            buffers.append(buffer)
        }
        
        lightNodes = []
        renderNodes = []
        var renderNodeQueue = [GLTFNode](scene.nodes)
        while !renderNodeQueue.isEmpty {
            let node = renderNodeQueue.removeFirst()
            if node.mesh != nil {
                renderNodes.append(node)
            }
            //if node.light != nil {
            //    lightNodes.append(node)
            //}
            renderNodeQueue.append(contentsOf: node.childNodes)
        }
        
        textures = []
        for image in asset.images {
            if let cgImage = image.cgImage, let dataProvider = cgImage.dataProvider, let rgbaBytes = dataProvider.data {
                let width = cgImage.width
                let height = cgImage.height
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                          width: width,
                                                                          height: height,
                                                                          mipmapped: false)
                descriptor.storageMode = .managed
                descriptor.usage = [.shaderRead]
                let texture = device.makeTexture(descriptor: descriptor)!
                texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                                mipmapLevel: 0,
                                withBytes: CFDataGetBytePtr(rgbaBytes),
                                bytesPerRow: 4 * width)
                textures.append(texture)
            }
        }
        
        for renderNode in renderNodes {
            guard let mesh = renderNode.mesh else { continue }
            for primitive in mesh.primitives {
            }
        }
    }

    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        for renderNode in renderNodes {
            guard let mesh = renderNode.mesh else { continue }
            
            for primitive in mesh.primitives {
            }
        }

        renderCommandEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
}

