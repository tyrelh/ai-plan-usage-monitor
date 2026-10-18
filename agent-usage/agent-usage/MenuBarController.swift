import AppKit
import SwiftUI

@MainActor
enum UsageColors {
    static func color(_ utilization: Double?) -> NSColor {
        guard let utilization else { return .tertiaryLabelColor }
        switch Int(utilization.rounded(.down)) {
        case ...50: return NSColor(srgbRed: 166/255, green: 227/255, blue: 161/255, alpha: 1)
        case ...75: return NSColor(srgbRed: 249/255, green: 226/255, blue: 175/255, alpha: 1)
        default: return NSColor(srgbRed: 243/255, green: 139/255, blue: 168/255, alpha: 1)
        }
    }
}

@MainActor
final class UsagePanelController {
    private let login: LoginSettings
    private let popover = NSPopover()

    init(stores: [ProviderStore], login: LoginSettings) {
        self.login = login
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(stores: stores, login: login))
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }
        else {
            login.reload()
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    let store: ProviderStore
    private let panel: UsagePanelController
    private let item: NSStatusItem
    private var appearanceObservation: NSKeyValueObservation?

    init(store: ProviderStore, panel: UsagePanelController) {
        self.store = store
        self.panel = panel
        // Fixed compact width reserves space during loading and failure too.
        item = NSStatusBar.system.statusItem(withLength: 132)
        super.init()
        item.autosaveName = "agent-usage-\(store.provider.rawValue)"
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.redraw() }
            }
        }
        store.onChange = { [weak self] in self?.redraw() }
        redraw()
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        panel.toggle(relativeTo: button)
    }

    private func redraw() {
        guard let button = item.button else { return }
        let windows = store.windows
        let marker = store.marker
        let logo = NSImage(named: store.provider.logo)
        let image = NSImage(size: NSSize(width: 128, height: 22))
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            defer { image.unlockFocus() }
            // Tint the SVG explicitly: the composite image also contains colored gauges.
            if let logo {
                let tinted = NSImage(size: NSSize(width: 17, height: 17))
                tinted.lockFocus()
                logo.draw(in: NSRect(x: 0, y: 0, width: 17, height: 17))
                NSColor.labelColor.setFill()
                NSRect(x: 0, y: 0, width: 17, height: 17).fill(using: .sourceIn)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: 1, y: 2.5, width: 17, height: 17))
            }
            for (index, window) in windows.enumerated() {
                let y: CGFloat = index == 0 ? 12 : 1
                drawText(window.label, x: 22, y: y, width: 27, alignment: .left)
                let track = NSRect(x: 50, y: y + 3, width: 34, height: 5)
                NSColor.labelColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
                if window.fraction > 0 {
                    UsageColors.color(window.utilization).setFill()
                    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * window.fraction, height: track.height), xRadius: 2, yRadius: 2).fill()
                }
                drawText(window.percent, x: 86, y: y, width: 31, alignment: .right)
            }
            drawText(marker, x: 119, y: 6, width: 9, alignment: .center)
        }
        image.isTemplate = false
        button.image = image
        let description = "\(store.provider.name): " + windows.map { "\($0.label) \($0.percent) used" }.joined(separator: ", ") + ". \(store.status)"
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    #if DEBUG
    // Opt-in local snapshots for checking the actual AppKit render without
    // capturing the user's desktop or writing any credential material.
    func writeDiagnostics(to directory: URL) throws {
        if let image = item.button?.image, let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("\(store.provider.rawValue)-menu.png"))
        }
        let summary = store.provider.name + "\n" + store.status + "\n"
            + store.windows.map { "\($0.label): \($0.percent)" }.joined(separator: "\n")
            + "\n" + (store.error ?? "")
        try summary.write(to: directory.appendingPathComponent("\(store.provider.rawValue)-status.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    private func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        (text as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 11), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
    }
}
