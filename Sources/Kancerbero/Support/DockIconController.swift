import AppKit
import Foundation
import KancerberoCore

// MARK: - Snapshot

/// Values the Dock view needs. Histories are copied (60 samples) so drawing
/// never touches the observable model from the Dock.
struct DockIconSnapshot {
    var cpuUsage: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuNice: Double = 0
    var cpuIdle: Double = 100
    var cpuUserHistory: [Double] = []
    var cpuSystemHistory: [Double] = []
    var cpuNiceHistory: [Double] = []

    var memoryUsedFraction: Double = 0
    /// App, Wired, Compressed, Cached Files, Free (bytes).
    var memorySegments: [Double] = []
    var memoryPressureHistory: [Int] = []
    var memoryPressureLevels: [Int] = []
    var memoryPressureLabel: String = "—"

    var rxRate: Double = 0
    var txRate: Double = 0
    var rxHistory: [Double] = []
    var txHistory: [Double] = []

    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []

    var gpuUsage: Double?
    var gpuHistory: [Double] = []

    var energyWatts: Double = 0
    var energyHistory: [Double] = []

    init() {}

    @MainActor
    init(model: AppModel) {
        let host = model.hostMetrics
        cpuUsage = host?.cpu.totalUsagePercent ?? 0
        cpuUser = host?.cpu.userPercent ?? 0
        cpuSystem = host?.cpu.systemPercent ?? 0
        cpuNice = host?.cpu.nicePercent ?? 0
        cpuIdle = host?.cpu.idlePercent ?? max(0, 100 - cpuUsage)
        cpuUserHistory = model.cpuUserHistory
        cpuSystemHistory = model.cpuSystemHistory
        cpuNiceHistory = model.cpuNiceHistory

        if let memory = host?.memory {
            memoryUsedFraction = memory.usedFraction
            memorySegments = [
                Double(memory.appMemoryBytes),
                Double(memory.wiredBytes),
                Double(memory.compressedBytes),
                Double(memory.cachedFileBytes),
                Double(memory.activityMonitorFreeBytes)
            ]
        }
        memoryPressureHistory = model.memoryPressureHistory
        memoryPressureLevels = model.memoryPressureLevelHistory
        memoryPressureLabel = host?.memory.pressureLabel ?? "—"

        rxRate = model.systemRates.rxBytesPerSecond
        txRate = model.systemRates.txBytesPerSecond
        rxHistory = model.rxHistory
        txHistory = model.txHistory

        diskReadRate = model.diskReadRate
        diskWriteRate = model.diskWriteRate
        diskReadHistory = model.diskReadHistory
        diskWriteHistory = model.diskWriteHistory

        gpuUsage = host?.gpu?.utilizationPercent
        gpuHistory = model.gpuUsageHistory

        energyWatts = model.energyUsageHistory.last ?? 0
        energyHistory = model.energyUsageHistory
    }
}

// MARK: - Controller

/// Owns the Dock tile content view and refreshes it independently of any
/// SwiftUI view, so the graph keeps updating after the window is closed.
@MainActor
final class DockIconController {
    private let view = DockIconView()
    private weak var model: AppModel?
    private var task: Task<Void, Never>?
    private var installedStyle: DockIconStyle = .applicationIcon

    func start(model: AppModel) {
        guard task == nil else { return }
        self.model = model
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func refresh() {
        guard let model else { return }
        let raw = UserDefaults.standard.string(forKey: KBPreferences.dockIconStyleKey) ?? ""
        let style = DockIconStyle(rawValue: raw) ?? .applicationIcon
        let dockTile = NSApp.dockTile

        if style == .applicationIcon {
            if installedStyle != .applicationIcon || dockTile.contentView != nil {
                dockTile.contentView = nil
                dockTile.display()
            }
            installedStyle = .applicationIcon
            return
        }

        let size = dockTile.size
        guard size.width > 0, size.height > 0 else { return }
        view.frame = NSRect(origin: .zero, size: size)
        view.apply(style: style, snapshot: DockIconSnapshot(model: model))
        if dockTile.contentView !== view {
            dockTile.contentView = view
        }
        installedStyle = style
        dockTile.display()
    }
}

// MARK: - Dock view

enum DockIconRenderError: Error {
    case bitmap
    case png
}

final class DockIconView: NSView {
    private enum Palette {
        static let background = NSColor(calibratedRed: 0.055, green: 0.065,
                                        blue: 0.10, alpha: 1)
        static let border = NSColor.white.withAlphaComponent(0.14)
        static let text = NSColor.white
        static let secondary = NSColor.white.withAlphaComponent(0.68)
        static let user = NSColor(calibratedRed: 0.16, green: 0.62,
                                  blue: 0.94, alpha: 1)
        static let system = NSColor(calibratedRed: 0.94, green: 0.56,
                                    blue: 0.18, alpha: 1)
        static let nice = NSColor(calibratedRed: 0.62, green: 0.42,
                                  blue: 0.95, alpha: 1)
        static let idle = NSColor(calibratedWhite: 0.34, alpha: 1)
        static let wired = NSColor(calibratedRed: 0.95, green: 0.42,
                                   blue: 0.30, alpha: 1)
        static let compressed = NSColor(calibratedRed: 0.72, green: 0.40,
                                        blue: 0.92, alpha: 1)
        static let cached = NSColor(calibratedRed: 0.20, green: 0.70,
                                    blue: 0.62, alpha: 1)
        static let free = NSColor(calibratedWhite: 0.35, alpha: 1)
        static let gpu = NSColor(calibratedRed: 0.36, green: 0.50,
                                 blue: 0.95, alpha: 1)
        static let energy = NSColor(calibratedRed: 0.95, green: 0.72,
                                    blue: 0.20, alpha: 1)
        static let diskRead = NSColor(calibratedRed: 0.94, green: 0.56,
                                      blue: 0.18, alpha: 1)
        static let diskWrite = NSColor(calibratedRed: 0.62, green: 0.42,
                                       blue: 0.95, alpha: 1)
    }

    private var style: DockIconStyle = .cpuUsage
    private var snapshot = DockIconSnapshot()

    override var isFlipped: Bool { true }

    func apply(style: DockIconStyle, snapshot: DockIconSnapshot) {
        self.style = style
        self.snapshot = snapshot
        needsDisplay = true
    }

    func renderPNG(to url: URL, size: CGFloat = 256) throws {
        let copy = DockIconView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        copy.apply(style: style, snapshot: snapshot)
        copy.layoutSubtreeIfNeeded()
        guard let representation = copy.bitmapImageRepForCachingDisplay(in: copy.bounds) else {
            throw DockIconRenderError.bitmap
        }
        copy.cacheDisplay(in: copy.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw DockIconRenderError.png
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        let frame = bounds.insetBy(dx: bounds.width * 0.02,
                                   dy: bounds.height * 0.02)
        let background = NSBezierPath(roundedRect: frame,
                                      xRadius: bounds.width * 0.22,
                                      yRadius: bounds.width * 0.22)
        Palette.background.setFill()
        background.fill()
        Palette.border.setStroke()
        background.lineWidth = max(1, bounds.width * 0.006)
        background.stroke()

        let content = bounds.insetBy(dx: bounds.width * 0.10,
                                     dy: bounds.height * 0.09)
        switch style {
        case .applicationIcon:
            drawApplicationHint(in: content)
        case .cpuUsage:
            drawCPUUsage(in: content)
        case .cpuHistory:
            drawCPUHistory(in: content)
        case .networkUsage:
            drawNetwork(in: content)
        case .diskActivity:
            drawDisk(in: content)
        case .memoryUsage:
            drawMemoryUsage(in: content)
        case .memoryPressure:
            drawMemoryPressure(in: content)
        case .gpuUsage:
            drawGPU(in: content)
        case .energyUsage:
            drawEnergy(in: content)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawApplicationHint(in content: NSRect) {
        if let logo = NSImage(named: "AppLogo") {
            let side = min(content.width, content.height) * 0.8
            let rect = NSRect(x: content.midX - side / 2,
                              y: content.midY - side / 2,
                              width: side, height: side)
            logo.draw(in: rect)
        }
    }

    private func drawCPUUsage(in content: NSRect) {
        drawLabel("CPU", in: relative(content, 0, 0, 0.65, 0.13))
        drawText(KBFormat.usagePercent(snapshot.cpuUsage),
                 in: relative(content, 0, 0.14, 1, 0.40),
                 size: content.height * 0.30, monospaced: true)
        let bar = relative(content, 0, 0.84, 1, 0.10)
        drawSegments([(snapshot.cpuUser, Palette.user),
                      (snapshot.cpuSystem, Palette.system),
                      (snapshot.cpuNice, Palette.nice),
                      (snapshot.cpuIdle, Palette.idle)],
                     in: bar)
    }

    private func drawCPUHistory(in content: NSRect) {
        drawLabel("CPU", in: relative(content, 0, 0, 0.5, 0.13))
        drawStatus(KBFormat.usagePercent(snapshot.cpuUsage),
                   in: relative(content, 0.5, 0, 0.5, 0.13))
        let graph = relative(content, 0, 0.24, 1, 0.72)
        drawStackedHistory(in: graph)
    }

    private func drawNetwork(in content: NSRect) {
        drawLabel("NET", in: relative(content, 0, 0, 0.4, 0.13))
        let size = content.height * 0.11
        drawStatus("↓ " + KBFormat.bitRate(snapshot.rxRate),
                   in: relative(content, 0, 0.10, 1, 0.14), size: size)
        drawStatus("↑ " + KBFormat.bitRate(snapshot.txRate),
                   in: relative(content, 0, 0.24, 1, 0.14), size: size)
        let graph = relative(content, 0, 0.44, 1, 0.52)
        drawMirrored(top: snapshot.rxHistory, bottom: snapshot.txHistory,
                     in: graph,
                     topColor: Palette.user, bottomColor: Palette.nice)
    }

    private func drawDisk(in content: NSRect) {
        drawLabel("DISK", in: relative(content, 0, 0, 0.4, 0.13))
        let size = content.height * 0.11
        drawStatus("R " + byteRate(snapshot.diskReadRate),
                   in: relative(content, 0, 0.10, 1, 0.14), size: size)
        drawStatus("W " + byteRate(snapshot.diskWriteRate),
                   in: relative(content, 0, 0.24, 1, 0.14), size: size)
        let graph = relative(content, 0, 0.44, 1, 0.52)
        drawMirrored(top: snapshot.diskReadHistory,
                     bottom: snapshot.diskWriteHistory,
                     in: graph,
                     topColor: Palette.diskRead, bottomColor: Palette.diskWrite)
    }

    private func drawMemoryUsage(in content: NSRect) {
        drawLabel("MEM", in: relative(content, 0, 0, 0.6, 0.13))
        drawText(KBFormat.percent(snapshot.memoryUsedFraction),
                 in: relative(content, 0, 0.14, 1, 0.40),
                 size: content.height * 0.30, monospaced: true)
        let bar = relative(content, 0, 0.72, 1, 0.14)
        drawSegments(snapshot.memorySegments.enumerated().map { index, value in
            let colors = [Palette.user, Palette.wired, Palette.compressed,
                          Palette.cached, Palette.free]
            return (value, colors[min(index, colors.count - 1)])
        }, in: bar)
    }

    private func drawMemoryPressure(in content: NSRect) {
        drawLabel("MEM", in: relative(content, 0, 0, 0.5, 0.13))
        if let percent = snapshot.memoryPressureHistory.last {
            drawStatus("\(percent)%", in: relative(content, 0.5, 0, 0.5, 0.13))
        }
        drawText(snapshot.memoryPressureLabel,
                 in: relative(content, 0, 0.14, 1, 0.34),
                 size: content.height * 0.26, monospaced: false)
        let graph = relative(content, 0, 0.44, 1, 0.52)
        drawPressureHistory(in: graph)
    }

    private func drawGPU(in content: NSRect) {
        drawLabel("GPU", in: relative(content, 0, 0, 0.6, 0.13))
        if let usage = snapshot.gpuUsage {
            drawText(KBFormat.usagePercent(usage),
                     in: relative(content, 0, 0.14, 1, 0.40),
                     size: content.height * 0.30, monospaced: true)
            drawSparkline(snapshot.gpuHistory,
                          in: relative(content, 0, 0.52, 1, 0.44),
                          color: Palette.gpu)
        } else {
            drawText("—", in: relative(content, 0, 0.20, 1, 0.40),
                     size: content.height * 0.26, monospaced: true)
            drawStatus("Unavailable", in: relative(content, 0, 0.66, 1, 0.14))
        }
    }

    private func drawEnergy(in content: NSRect) {
        drawLabel("PWR", in: relative(content, 0, 0, 0.6, 0.13))
        drawText(String(format: "%.1f W", snapshot.energyWatts),
                 in: relative(content, 0, 0.14, 1, 0.40),
                 size: content.height * 0.26, monospaced: true)
        drawSparkline(snapshot.energyHistory,
                      in: relative(content, 0, 0.52, 1, 0.44),
                      color: Palette.energy)
    }

    // MARK: Layout helpers

    private func relative(_ content: NSRect, _ x: CGFloat, _ y: CGFloat,
                          _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: content.minX + content.width * x,
               y: content.minY + content.height * y,
               width: content.width * width,
               height: content.height * height)
    }

    private func drawLabel(_ text: String, in rect: NSRect) {
        drawText(text, in: rect, size: rect.height * 0.95,
                 color: Palette.secondary, monospaced: false)
    }

    private func drawStatus(_ text: String, in rect: NSRect,
                            size: CGFloat? = nil) {
        drawText(text, in: rect, size: size ?? rect.height * 0.95,
                 color: Palette.secondary, monospaced: true, alignment: .right)
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat,
                          color: NSColor = Palette.text,
                          monospaced: Bool,
                          alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let font = monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            : NSFont.systemFont(ofSize: size, weight: .semibold)
        NSAttributedString(string: text,
                           attributes: [.font: font,
                                        .foregroundColor: color,
                                        .paragraphStyle: paragraph])
            .draw(in: rect)
    }

    // MARK: Charts

    private func drawSegments(_ values: [(Double, NSColor)], in rect: NSRect) {
        let total = max(values.reduce(0) { $0 + max(0, $1.0) }, 0.0001)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: rect.height / 2,
                                yRadius: rect.height / 2)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        var x = rect.minX
        for (value, color) in values {
            let width = rect.width * CGFloat(max(0, value) / total)
            color.setFill()
            NSBezierPath(rect: NSRect(x: x, y: rect.minY, width: width, height: rect.height)).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawStackedHistory(in rect: NSRect) {
        let count = min(60, min(snapshot.cpuUserHistory.count,
                                min(snapshot.cpuSystemHistory.count,
                                    snapshot.cpuNiceHistory.count)))
        guard count > 1, rect.width > 0, rect.height > 0 else {
            drawPlaceholder(in: rect)
            return
        }
        let users = Array(snapshot.cpuUserHistory.suffix(count))
        let systems = Array(snapshot.cpuSystemHistory.suffix(count))
        let nices = Array(snapshot.cpuNiceHistory.suffix(count))
        var userTops: [Double] = []
        var totalTops: [Double] = []
        for index in 0..<count {
            let userTop = systems[index] + users[index]
            userTops.append(userTop)
            totalTops.append(userTop + nices[index])
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        fillBand(lower: totalTops, upper: Array(repeating: 100, count: count),
                 in: rect, color: Palette.idle.withAlphaComponent(0.35))
        fillBand(lower: userTops, upper: totalTops, in: rect,
                 color: Palette.nice.withAlphaComponent(0.8))
        fillBand(lower: systems, upper: userTops, in: rect,
                 color: Palette.user.withAlphaComponent(0.85))
        fillBand(lower: Array(repeating: 0, count: count), upper: systems,
                 in: rect, color: Palette.system.withAlphaComponent(0.9))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func fillBand(lower: [Double], upper: [Double], in rect: NSRect,
                          color: NSColor) {
        guard lower.count > 1, lower.count == upper.count else { return }
        let stepX = rect.width / CGFloat(lower.count - 1)
        func point(_ index: Int, _ value: Double) -> NSPoint {
            let normalized = min(max(value, 0), 100) / 100
            return NSPoint(x: rect.minX + CGFloat(index) * stepX,
                           y: rect.maxY - CGFloat(normalized) * rect.height)
        }
        let path = NSBezierPath()
        path.move(to: point(0, lower[0]))
        for index in 1..<lower.count {
            path.line(to: point(index, lower[index]))
        }
        for index in stride(from: lower.count - 1, through: 0, by: -1) {
            path.line(to: point(index, upper[index]))
        }
        path.close()
        color.setFill()
        path.fill()
    }

    private func drawSparkline(_ values: [Double], in rect: NSRect,
                               color: NSColor) {
        guard values.count > 1, rect.width > 0, rect.height > 0 else {
            drawPlaceholder(in: rect)
            return
        }
        let data = Array(suffix60(values))
        let peak = max(data.max() ?? 1, 0.0001)
        let stepX = rect.width / CGFloat(max(1, data.count - 1))
        let line = NSBezierPath()
        let area = NSBezierPath()
        area.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        for (index, value) in data.enumerated() {
            let x = rect.minX + CGFloat(index) * stepX
            let y = rect.maxY - CGFloat(min(max(value, 0), peak) / peak) * rect.height
            let point = NSPoint(x: x, y: y)
            if index == 0 {
                line.move(to: point)
                area.line(to: point)
            } else {
                line.line(to: point)
                area.line(to: point)
            }
        }
        area.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        area.close()
        color.withAlphaComponent(0.22).setFill()
        area.fill()
        color.setStroke()
        line.lineWidth = max(1, rect.height * 0.05)
        line.stroke()
    }

    private func drawMirrored(top: [Double], bottom: [Double], in rect: NSRect,
                              topColor: NSColor, bottomColor: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        let topValues = suffix60(top)
        let bottomValues = suffix60(bottom)
        guard topValues.count > 1 || bottomValues.count > 1 else {
            drawPlaceholder(in: rect)
            return
        }
        let peak = max(max(topValues.max() ?? 0, bottomValues.max() ?? 0), 0.0001)
        let middle = rect.midY
        drawHalf(topValues, baseline: middle, direction: -1,
                 halfHeight: rect.height / 2 - 2, peak: peak,
                 color: topColor, in: rect)
        drawHalf(bottomValues, baseline: middle, direction: 1,
                 halfHeight: rect.height / 2 - 2, peak: peak,
                 color: bottomColor, in: rect)
        Palette.border.setStroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: rect.minX, y: middle))
        divider.line(to: NSPoint(x: rect.maxX, y: middle))
        divider.lineWidth = max(0.5, rect.height * 0.01)
        divider.stroke()
    }

    private func drawHalf(_ values: [Double], baseline: CGFloat,
                          direction: CGFloat, halfHeight: CGFloat,
                          peak: Double, color: NSColor, in rect: NSRect) {
        guard values.count > 1, halfHeight > 0 else { return }
        let stepX = rect.width / CGFloat(values.count - 1)
        let line = NSBezierPath()
        let area = NSBezierPath()
        area.move(to: NSPoint(x: rect.minX, y: baseline))
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) * stepX
            let normalized = CGFloat(min(max(value, 0), peak) / peak)
            let y = baseline + direction * normalized * halfHeight
            let point = NSPoint(x: x, y: y)
            if index == 0 {
                line.move(to: point)
                area.line(to: point)
            } else {
                line.line(to: point)
                area.line(to: point)
            }
        }
        area.line(to: NSPoint(x: rect.maxX, y: baseline))
        area.close()
        color.withAlphaComponent(0.22).setFill()
        area.fill()
        color.setStroke()
        line.lineWidth = max(1, halfHeight * 0.06)
        line.stroke()
    }

    private func drawPressureHistory(in rect: NSRect) {
        let count = min(snapshot.memoryPressureHistory.count,
                        snapshot.memoryPressureLevels.count)
        guard count > 1, rect.width > 0, rect.height > 0 else {
            drawPlaceholder(in: rect)
            return
        }
        let values = Array(snapshot.memoryPressureHistory.suffix(count))
        let levels = Array(snapshot.memoryPressureLevels.suffix(count))
        let stepX = rect.width / CGFloat(count - 1)
        let line = NSBezierPath()
        let area = NSBezierPath()
        area.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        for index in 0..<count {
            let percent = min(max(Double(values[index]), 0), 100) / 100
            let point = NSPoint(x: rect.minX + CGFloat(index) * stepX,
                                y: rect.maxY - CGFloat(percent) * rect.height)
            if index == 0 {
                line.move(to: point)
                area.line(to: point)
            } else {
                line.line(to: point)
                area.line(to: point)
            }
        }
        area.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        area.close()
        let color = pressureColor(levels.last ?? 0)
        color.withAlphaComponent(0.20).setFill()
        area.fill()
        color.setStroke()
        line.lineWidth = max(1, rect.height * 0.05)
        line.stroke()
    }

    private func pressureColor(_ level: Int) -> NSColor {
        switch level {
        case 1: return .systemGreen
        case 2, 3: return .systemYellow
        default: return level >= 4 ? .systemRed : .secondaryLabelColor
        }
    }

    private func drawPlaceholder(in rect: NSRect) {
        Palette.border.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 1))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 1))
        path.lineWidth = max(1, rect.height * 0.03)
        path.stroke()
    }

    private func suffix60(_ values: [Double]) -> [Double] {
        Array(values.suffix(60))
    }

    private func byteRate(_ bytesPerSecond: Double) -> String {
        let bytes = UInt64(max(0, bytesPerSecond))
        return bytes == 0 ? "0 B/s" : KBFormat.bytes(bytes) + "/s"
    }
}
