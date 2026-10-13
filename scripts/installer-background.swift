import AppKit

// Finder places the actual draggable app and Applications icons over this backdrop.
let size = NSSize(width: 660, height: 440)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(
        in: NSRect(x: 40, y: y, width: 580, height: 50),
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
}
text("A little closer.", y: 330, font: .systemFont(ofSize: 34, weight: .semibold), color: .black)
text("Drag Sofla to Applications.", y: 284, font: .systemFont(ofSize: 16), color: .darkGray)
text("→", y: 186, font: .systemFont(ofSize: 36, weight: .light), color: .gray)
if CommandLine.arguments.contains("--unnotarized") {
    text(
        "If macOS blocks the first launch:", y: 72, font: .systemFont(ofSize: 13), color: .darkGray)
    text(
        "System Settings → Privacy & Security → Open Anyway", y: 46, font: .systemFont(ofSize: 13),
        color: .darkGray)
    text(
        "Not notarized by Apple · macOS 26+ · Apple silicon", y: 12, font: .systemFont(ofSize: 11),
        color: .gray)
} else {
    text(
        "Then open Sofla. Make yourself at home.", y: 64, font: .systemFont(ofSize: 14),
        color: .darkGray)
    text("macOS 26+ · Apple silicon", y: 24, font: .systemFont(ofSize: 11), color: .gray)
}
image.unlockFocus()
guard (2...3).contains(CommandLine.arguments.count),
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("Usage: installer-background.swift output.png") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
