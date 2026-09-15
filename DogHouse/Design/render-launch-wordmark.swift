// Renders the "DogHouse" launch wordmark to a 3x PNG imageset, using the
// same font as Font.dhDisplay (system largeTitle, rounded, black): 34pt.
// Both LaunchScreen.storyboard and LaunchSplashView show this image, so the
// hand-off frame matches exactly.   swift Design/render-launch-wordmark.swift
import AppKit

let text = "DogHouse"
let scale: CGFloat = 3
let base = NSFont.systemFont(ofSize: 34, weight: .black)
let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: 34) ?? base
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let str = NSAttributedString(string: text, attributes: attrs)
let bounds = str.boundingRect(with: NSSize(width: 1000, height: 200), options: [.usesLineFragmentOrigin])
let w = Int(ceil(bounds.width) + 2), h = Int(ceil(font.ascender - font.descender) + 2)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(w) * scale), pixelsHigh: Int(CGFloat(h) * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
str.draw(at: NSPoint(x: 1, y: 1 - font.descender + (CGFloat(h) - 2 - (font.ascender - font.descender)) / 2 + font.descender))
NSGraphicsContext.restoreGraphicsState()
let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("DogHouse/Assets.xcassets/LaunchWordmark.imageset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("LaunchWordmark@3x.png"))
try! """
{
  "images" : [
    {
      "filename" : "LaunchWordmark@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

""".write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(dir.path) \(w)x\(h) pt")
