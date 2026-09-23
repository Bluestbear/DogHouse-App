//
//  FlatBootView.swift
//  DogHouse
//
//  The old hiking boot that kicks the dog out in SendToDogHouseAnimation.
//  Drawn flat like the rest of the app (DoghouseScene, AvatarView): soft
//  two-tone fills, thin 35% black outlines, faint white highlights. Faces
//  right; drawn in a 300 × 200 design space and scaled to its frame.
//

import SwiftUI

struct FlatBootView: View {
    static let aspect: CGFloat = 200.0 / 300.0

    private let leather = Gradient(colors: [Color(red: 0.80, green: 0.49, blue: 0.24),
                                            Color(red: 0.68, green: 0.38, blue: 0.18)])
    private let darkLeather = Color(red: 0.56, green: 0.30, blue: 0.14)
    private let collarTan = Color(red: 0.88, green: 0.62, blue: 0.36)
    private let tongueTan = Color(red: 0.84, green: 0.56, blue: 0.30)
    private let rubber = Color(red: 0.30, green: 0.27, blue: 0.26)
    private let rubberDark = Color(red: 0.22, green: 0.20, blue: 0.19)
    private let lace = Color(red: 0.98, green: 0.92, blue: 0.78)
    private let brass = Color(red: 0.88, green: 0.72, blue: 0.30)
    private let patchOlive = Color(red: 0.52, green: 0.56, blue: 0.32)
    private let outline = Color.black.opacity(0.35)

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 300, y: size.height / 200)
            drawSole(&ctx)
            fillOutlined(&ctx, tongue, .color(tongueTan))
            fillOutlined(&ctx, upper, .linearGradient(leather, startPoint: CGPoint(x: 0, y: 10),
                                                      endPoint: CGPoint(x: 0, y: 150)))
            fillOutlined(&ctx, heelCounter, .color(darkLeather))
            fillOutlined(&ctx, toeCap, .color(darkLeather))
            // Stitching along the toe cap and heel seams
            let stitch = StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4])
            ctx.stroke(toeSeam, with: .color(lace.opacity(0.55)), style: stitch)
            ctx.stroke(heelSeam, with: .color(lace.opacity(0.55)), style: stitch)
            // Lit edge across the top of the foot
            ctx.stroke(vampHighlight, with: .color(.white.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            drawPatch(&ctx)
            fillOutlined(&ctx, collar, .color(collarTan))
            drawLaces(&ctx)
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func fillOutlined(_ ctx: inout GraphicsContext, _ path: Path, _ shading: GraphicsContext.Shading) {
        ctx.fill(path, with: shading)
        ctx.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    // MARK: Shapes

    private var upper: Path {
        Path { p in
            p.move(to: CGPoint(x: 36, y: 24))
            p.addLine(to: CGPoint(x: 130, y: 16))
            // Front of the shaft down to the instep
            p.addQuadCurve(to: CGPoint(x: 152, y: 80), control: CGPoint(x: 148, y: 34))
            // Over the top of the foot
            p.addQuadCurve(to: CGPoint(x: 240, y: 98), control: CGPoint(x: 192, y: 86))
            // Round, slightly bulbous toe
            p.addQuadCurve(to: CGPoint(x: 292, y: 148), control: CGPoint(x: 294, y: 102))
            p.addLine(to: CGPoint(x: 24, y: 148))
            // Heel, then up the back of the shaft
            p.addQuadCurve(to: CGPoint(x: 30, y: 98), control: CGPoint(x: 14, y: 126))
            p.addQuadCurve(to: CGPoint(x: 36, y: 24), control: CGPoint(x: 40, y: 60))
            p.closeSubpath()
        }
    }

    private var tongue: Path {
        Path { p in
            p.move(to: CGPoint(x: 116, y: 24))
            p.addQuadCurve(to: CGPoint(x: 158, y: 6), control: CGPoint(x: 128, y: 2))
            p.addQuadCurve(to: CGPoint(x: 160, y: 32), control: CGPoint(x: 170, y: 16))
            p.addLine(to: CGPoint(x: 138, y: 44))
            p.closeSubpath()
        }
    }

    /// The padded, rolled-over cuff at the top of the shaft.
    private var collar: Path {
        Path { p in
            p.move(to: CGPoint(x: 28, y: 28))
            p.addQuadCurve(to: CGPoint(x: 136, y: 18), control: CGPoint(x: 80, y: 10))
            p.addQuadCurve(to: CGPoint(x: 138, y: 36), control: CGPoint(x: 144, y: 26))
            p.addQuadCurve(to: CGPoint(x: 32, y: 46), control: CGPoint(x: 84, y: 30))
            p.addQuadCurve(to: CGPoint(x: 28, y: 28), control: CGPoint(x: 22, y: 38))
            p.closeSubpath()
        }
    }

    private var toeCap: Path {
        Path { p in
            p.move(to: CGPoint(x: 224, y: 97))
            p.addQuadCurve(to: CGPoint(x: 292, y: 148), control: CGPoint(x: 293, y: 101))
            p.addLine(to: CGPoint(x: 204, y: 148))
            p.addQuadCurve(to: CGPoint(x: 224, y: 97), control: CGPoint(x: 196, y: 114))
            p.closeSubpath()
        }
    }

    private var heelCounter: Path {
        Path { p in
            p.move(to: CGPoint(x: 24, y: 148))
            p.addLine(to: CGPoint(x: 92, y: 148))
            p.addQuadCurve(to: CGPoint(x: 29, y: 100), control: CGPoint(x: 88, y: 102))
            p.addQuadCurve(to: CGPoint(x: 24, y: 148), control: CGPoint(x: 14, y: 126))
            p.closeSubpath()
        }
    }

    private var toeSeam: Path {
        Path { p in
            p.move(to: CGPoint(x: 222, y: 104))
            p.addQuadCurve(to: CGPoint(x: 212, y: 142), control: CGPoint(x: 204, y: 118))
        }
    }

    private var heelSeam: Path {
        Path { p in
            p.move(to: CGPoint(x: 34, y: 107))
            p.addQuadCurve(to: CGPoint(x: 84, y: 142), control: CGPoint(x: 80, y: 110))
        }
    }

    private var vampHighlight: Path {
        Path { p in
            p.move(to: CGPoint(x: 164, y: 88))
            p.addQuadCurve(to: CGPoint(x: 234, y: 104), control: CGPoint(x: 200, y: 92))
        }
    }

    // MARK: Details

    private func drawSole(_ ctx: inout GraphicsContext) {
        // Chunky tread lugs under a rubber midsole
        for x in stride(from: 26.0, through: 272.0, by: 22.0) {
            let lug = Path(roundedRect: CGRect(x: x, y: 160, width: 14, height: 14), cornerRadius: 3)
            fillOutlined(&ctx, lug, .color(rubberDark))
        }
        let sole = Path(roundedRect: CGRect(x: 16, y: 142, width: 282, height: 24), cornerRadius: 10)
        fillOutlined(&ctx, sole, .color(rubber))
        // Lit top edge of the sole
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 26, y: 146))
            p.addLine(to: CGPoint(x: 288, y: 146))
        }, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    /// A worn-out boot has been mended: a square of olive cloth, stitched on.
    private func drawPatch(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 66, y: 118)
        c.rotate(by: .degrees(-8))
        let patch = Path(roundedRect: CGRect(x: -12, y: -11, width: 24, height: 22), cornerRadius: 3)
        c.fill(patch, with: .color(patchOlive))
        c.stroke(patch, with: .color(outline), lineWidth: 1.2)
        let inset = Path(roundedRect: CGRect(x: -8.5, y: -7.5, width: 17, height: 15), cornerRadius: 2)
        c.stroke(inset, with: .color(lace.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
    }

    private func drawLaces(_ ctx: inout GraphicsContext) {
        let eyelets = [CGPoint(x: 128, y: 50), CGPoint(x: 134, y: 64),
                       CGPoint(x: 142, y: 77), CGPoint(x: 156, y: 88)]
        let laceStyle = StrokeStyle(lineWidth: 4, lineCap: .round)
        // Cross-laces running from each eyelet over the front edge
        for e in eyelets.dropFirst() {
            ctx.stroke(Path { p in
                p.move(to: e)
                p.addLine(to: CGPoint(x: e.x + 16, y: e.y - 12))
            }, with: .color(lace), style: laceStyle)
        }
        // One loose lace dangling from the top eyelet
        let loose = Path { p in
            p.move(to: eyelets[0])
            p.addQuadCurve(to: CGPoint(x: 116, y: 118), control: CGPoint(x: 102, y: 80))
        }
        ctx.stroke(loose, with: .color(outline), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
        ctx.stroke(loose, with: .color(lace), style: laceStyle)
        ctx.fill(Path(ellipseIn: CGRect(x: 112.5, y: 115, width: 7, height: 7)), with: .color(darkLeather))
        for e in eyelets {
            let ring = Path(ellipseIn: CGRect(x: e.x - 5, y: e.y - 5, width: 10, height: 10))
            fillOutlined(&ctx, ring, .color(brass))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 2, y: e.y - 2, width: 4, height: 4)),
                     with: .color(rubberDark))
        }
    }
}

#Preview {
    FlatBootView()
        .frame(width: 300)
        .padding()
        .background(Color(red: 0.25, green: 0.27, blue: 0.33))
}
