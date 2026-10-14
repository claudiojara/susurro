// Renders an SVG file into a square PNG with WebKit, which supports the gradients and filters that the SVG
// renderers of ImageMagick and NSImage leave out. Usage: swift scripts/render-svg.swift <input.svg> <output.png> <pixels>
import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let pixels = Int(arguments[3]), pixels > 0 else {
    FileHandle.standardError.write(Data("usage: render-svg.swift <input.svg> <output.png> <pixels>\n".utf8))
    exit(64)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let pixels: Int
    let output: URL

    init(input: URL, output: URL, pixels: Int) throws {
        self.pixels = pixels
        self.output = output
        let size = CGFloat(pixels)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        webView.navigationDelegate = self
        let svg = try String(contentsOf: input, encoding: .utf8)
        let html = """
            <!doctype html><html><head><style>
            html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
            svg { display: block; width: \(pixels)px; height: \(pixels)px; }
            </style></head><body>\(svg)</body></html>
            """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        configuration.snapshotWidth = NSNumber(value: pixels)
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image else {
                FileHandle.standardError.write(Data("snapshot failed: \(String(describing: error))\n".utf8))
                exit(1)
            }
            self.write(image)
            exit(0)
        }
    }

    // The snapshot can come back at the screen's backing scale, so it is redrawn at exactly the requested pixels.
    private func write(_ image: NSImage) {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { exit(1) }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        context?.imageInterpolation = .high
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try data.write(to: output)
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    do {
        let renderer = try Renderer(input: input, output: output, pixels: pixels)
        withExtendedLifetime(renderer) { app.run() }
    } catch {
        FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
        exit(1)
    }
}
