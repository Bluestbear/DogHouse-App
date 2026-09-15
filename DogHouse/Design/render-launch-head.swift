// Renders LaunchHead.png from the real AvatarView, so the launch storyboard
// shows exactly what LaunchSplashView draws a frame later — same geometry,
// same colours, no hand-drawn duplicate to keep in sync. The Python generator
// (make-app-icon-dog.py) still owns the icon and LaunchFur; the head PNG it
// used to draw had slightly different pupils/smile/tag and the face visibly
// popped at the hand-off.
//
//   swiftc Design/render-launch-head.swift DogHouse/Models/Avatar.swift \
//       DogHouse/Views/Avatar/AvatarView.swift -o <tmp>/render-launch-head
//   <tmp>/render-launch-head <out.png>
//
// The output is raw sRGB; Design/compensate-launch-head.py applies the same
// Display P3 re-encoding as make-app-icon-dog.py and writes the imageset.

import SwiftUI
import AppKit

@main
@MainActor
struct RenderLaunchHead {
    // HEAD_BOX in avatar units (x0, y0, x1, y1), 20 px per unit — keep in step
    // with make-app-icon-dog.py and the storyboard's 1120:1280 aspect constraint.
    static let headBox = (x0: -32.0, y0: -35.0, x1: 32.0, y1: 21.0)
    static let pxPerUnit = 20.0

    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "LaunchHead-raw.png"

        let view = AvatarView(
            avatar: DogAvatar.avatar(for: "dog_1"),
            mood: .happy,
            size: 80,
            blinks: false,
            showsTail: false,
            headOnly: true,
            blinkOverride: false
        )
        .frame(width: 80, height: 80)

        let renderer = ImageRenderer(content: view)
        renderer.scale = pxPerUnit   // 80 units -> 1600 px, avatar centre at (800, 800)
        renderer.isOpaque = false
        guard let full = renderer.cgImage else { fatalError("ImageRenderer produced no image") }
        precondition(full.width == 1600 && full.height == 1600, "unexpected render size \(full.width)x\(full.height)")

        // Avatar coords: origin at view centre, y down — same direction as image rows.
        let crop = CGRect(
            x: 800 + headBox.x0 * pxPerUnit,
            y: 800 + headBox.y0 * pxPerUnit,
            width: (headBox.x1 - headBox.x0) * pxPerUnit,
            height: (headBox.y1 - headBox.y0) * pxPerUnit
        )
        guard let head = full.cropping(to: crop) else { fatalError("crop failed") }

        let rep = NSBitmapImageRep(cgImage: head)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("wrote \(out) \(head.width)x\(head.height)")
    }
}
