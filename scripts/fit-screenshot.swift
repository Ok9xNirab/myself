// Fits window screenshots onto a 2880 × 1800 canvas for the Mac App Store, which only takes 2880×1800, 2560×1600,
// 1440×900 or 1280×800. The window (with its shadow, as ⇧⌘4 then Space captures it) is centred on a soft blue
// gradient like the website's, and the result has no transparency.
//
//   swift scripts/fit-screenshot.swift ~/Desktop/Screenshot*.png
//
// Writes "<name> (App Store).png" next to each input.
import AppKit

let canvas = CGSize(width: 2880, height: 1800)
let margin: CGFloat = 120

func fit(_ path: String) throws {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "fit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't read \(url.path)"])
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
    // Background: the website's blue gradient.
    let colors = [CGColor(srgbRed: 0.75, green: 0.79, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.43, green: 0.50, blue: 0.81, alpha: 1)]
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: 0, y: 0), options: [])
    // The window, scaled to fit inside the margins (never enlarged past its own pixels), centred.
    let size = CGSize(width: image.width, height: image.height)
    let scale = min((canvas.width - 2 * margin) / size.width, (canvas.height - 2 * margin) / size.height, 1)
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: (canvas.width - drawn.width) / 2, y: (canvas.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
    guard let result = context.makeImage() else { return }
    let out = url.deletingPathExtension().path + " (App Store).png"
    let rep = NSBitmapImageRep(cgImage: result)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("\(url.lastPathComponent) (\(image.width)×\(image.height)) → \((out as NSString).lastPathComponent)")
}

let paths = CommandLine.arguments.dropFirst()
if paths.isEmpty { print("usage: swift scripts/fit-screenshot.swift <screenshot.png>…") }
for path in paths {
    do { try fit(path) } catch { print(error.localizedDescription) }
}
