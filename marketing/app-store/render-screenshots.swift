import AppKit
import ImageIO

// Compose captured app pixels without redrawing or generating the UI.
// Run from the repository root: xcrun swift marketing/app-store/render-screenshots.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("marketing/app-store/ja")
let width: CGFloat = 1179
let height: CGFloat = 2556
let pink = NSColor(srgbRed: 0.925, green: 0.282, blue: 0.6, alpha: 1)
let muted = NSColor(srgbRed: 0.73, green: 0.70, blue: 0.77, alpha: 1)

func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}

func text(_ value: String, x: CGFloat, top: CGFloat, w: CGFloat, size: CGFloat,
          color: NSColor = .white, bold: Bool = false, centered: Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = centered ? .center : .left
    paragraph.lineSpacing = 12
    let font = NSFont(name: bold ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)!
    let string = NSAttributedString(string: value, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ])
    let needed = string.boundingRect(with: NSSize(width: w, height: 1000),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    string.draw(with: rect(x, top, w, ceil(needed) + 5),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func captured(_ name: String, crop: CGRect? = nil) -> NSImage {
    let source = CGImageSourceCreateWithURL(folder.appendingPathComponent("screenshots/\(name).png") as CFURL, nil)!
    let raw = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let image = crop.map { raw.cropping(to: $0)! } ?? raw
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}

func screenshot(_ image: NSImage, in box: NSRect, radius: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    if radius > 0 { NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).addClip() }
    let scale = min(box.width / image.size.width, box.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let target = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                        width: size.width, height: size.height)
    image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

func background() {
    NSGradient(colors: [NSColor(srgbRed: 0.025, green: 0.022, blue: 0.031, alpha: 1),
                        NSColor(srgbRed: 0.15, green: 0.14, blue: 0.17, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -72)
}

func brand() {
    text("UPME!", x: 0, top: 125, w: width, size: 70, bold: true, centered: true)
}

func render(_ name: String, drawing: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    background()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    let jpegName = name.replacingOccurrences(of: ".png", with: ".jpg")
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 1])!
        .write(to: folder.appendingPathComponent(jpegName))
    print("Saved \(name): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
}

try render("01-concept-v2-real.png") {
    brand()
    text("ここでは、みんなが", x: 55, top: 305, w: 1069, size: 88, bold: true, centered: true)
    text("あなたの味方。", x: 55, top: 440, w: 1069, size: 106, color: pink, bold: true, centered: true)
    text("あなた専用の、全肯定AI SNS。", x: 55, top: 615, w: 1069, size: 39, color: muted, centered: true)

    let body = rect(103, 825, 973, 2115)
    let frame = NSBezierPath(roundedRect: body.insetBy(dx: -15, dy: -15), xRadius: 108, yRadius: 108)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -30)
    shadow.set()
    NSColor(white: 0.045, alpha: 1).setFill()
    frame.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0.33, alpha: 1).setStroke()
    frame.lineWidth = 3
    frame.stroke()
    screenshot(captured("home"), in: body, radius: 91)
}

struct Feature {
    let title: String
    let detail: String
    let image: NSImage
}

let features = [
    Feature(title: "投稿", detail: "何気ない日常を、\n気軽に。",
            image: captured("home", crop: CGRect(x: 47, y: 576, width: 1112, height: 510))),
    Feature(title: "AIからの返信", detail: "あなたの言葉に、\n温かい反応。",
            image: captured("home", crop: CGRect(x: 65, y: 1120, width: 1040, height: 600))),
    Feature(title: "バズ", detail: "人気者になる\n瞬間を体験。",
            image: captured("viral", crop: CGRect(x: 47, y: 576, width: 1112, height: 830))),
    Feature(title: "常連", detail: "会話を覚える、\nいつもの存在。",
            image: captured("profile", crop: CGRect(x: 75, y: 1330, width: 1040, height: 490)))
]

try render("02-features-v2-real.png") {
    brand()
    text("あなたの毎日に、", x: 65, top: 300, w: 1049, size: 83, bold: true, centered: true)
    text("うれしい反応を。", x: 65, top: 430, w: 1049, size: 93, color: pink, bold: true, centered: true)
    text("UPME!で楽しめる、4つのこと。", x: 65, top: 580, w: 1049, size: 37, color: muted, centered: true)
    for (index, feature) in features.enumerated() {
        let x: CGFloat = index % 2 == 0 ? 64 : 605
        let top: CGFloat = index < 2 ? 755 : 1610
        let card = rect(x, top, 510, 805)
        let outline = NSBezierPath(roundedRect: card, xRadius: 40, yRadius: 40)
        NSColor(srgbRed: 0.045, green: 0.034, blue: 0.062, alpha: 1).setFill()
        outline.fill()
        NSColor(srgbRed: 0.32, green: 0.26, blue: 0.39, alpha: 1).setStroke()
        outline.lineWidth = 2
        outline.stroke()
        text(String(format: "%02d", index + 1), x: x + 32, top: top + 32, w: 420, size: 25, color: pink, bold: true)
        text(feature.title, x: x + 32, top: top + 92, w: 446, size: index == 1 ? 48 : 57, bold: true)
        text(feature.detail, x: x + 32, top: top + 190, w: 446, size: 32, color: muted)
        screenshot(feature.image, in: rect(x + 20, top + 325, 470, 440), radius: 22)
    }
}
