import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Native format conversion only: preserve artwork, proportions, margins and alpha.
// No design redraw, cropping, masking, or new effects are applied here.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Icon packaging: " + message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else { fail("Expected a PNG master and an .iconset output folder.") }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard output.pathExtension == "iconset" else { fail("Output must be an .iconset folder.") }
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Cannot decode the icon master.") }
guard master.width == master.height, master.width >= 1024 else { fail("Master must be square and at least 1024 pixels.") }
guard [.first, .last, .premultipliedFirst, .premultipliedLast].contains(master.alphaInfo) else {
    fail("Master must include transparent outer edges.")
}
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, pixels) in sizes {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: pixels * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
        fail("Cannot allocate the icon-size buffer.")
    }
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let image = context.makeImage(), let data = context.data else { fail("Cannot render an icon size.") }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    for (x, y) in [(0, 0), (pixels - 1, 0), (0, pixels - 1), (pixels - 1, pixels - 1)] {
        guard bytes[(y * pixels + x) * 4 + 3] == 0 else { fail("Outer corner is not transparent.") }
    }
    // High-quality downsampling may round alpha a few levels below 255.
    guard bytes[((pixels / 2) * pixels + pixels / 2) * 4 + 3] >= 250 else {
        fail("Icon interior is unexpectedly transparent at \(pixels) px.")
    }
    let url = output.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("Cannot create a PNG icon size.")
    }
    // No source metadata, generation prompt or personal source path is exported.
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot save an icon size.") }
}
print("Verified 10 standard/Retina icon sizes (16–1024 px), transparent corners and near-opaque interiors.")
