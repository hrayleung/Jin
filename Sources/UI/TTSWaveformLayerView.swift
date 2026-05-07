import AppKit

final class TTSWaveformLayerView: NSView {
    private let playedLayer = CAShapeLayer()
    private let remainingLayer = CAShapeLayer()
    private var levels: [CGFloat] = []
    private var progress: Double = 0
    private var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        updateContentsScale()

        layer?.addSublayer(remainingLayer)
        layer?.addSublayer(playedLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        remainingLayer.frame = bounds
        playedLayer.frame = bounds
        updatePaths()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePaths()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
        updatePaths()
    }

    func apply(levels: [CGFloat], progress: Double, isActive: Bool) {
        self.levels = levels
        self.progress = progress
        self.isActive = isActive
        updatePaths()
    }

    private func updatePaths() {
        guard bounds.width > 0, bounds.height > 0, !levels.isEmpty else {
            remainingLayer.path = nil
            playedLayer.path = nil
            return
        }

        let desiredBarWidth: CGFloat = 2.5
        let desiredSpacing: CGFloat = 1.5
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 18
        let count = levels.count

        let totalDesiredWidth = CGFloat(count) * desiredBarWidth + CGFloat(max(0, count - 1)) * desiredSpacing
        let scale = min(1, bounds.width / max(totalDesiredWidth, 1))
        let barWidth = max(2, desiredBarWidth * scale)
        let barSpacing = max(1, desiredSpacing * scale)
        let totalWidth = CGFloat(count) * barWidth + CGFloat(max(0, count - 1)) * barSpacing
        let originX = max(0, (bounds.width - totalWidth) / 2)
        let midY = bounds.midY

        let playedPath = CGMutablePath()
        let remainingPath = CGMutablePath()

        for (index, level) in levels.enumerated() {
            let clamped = max(0, min(1, level))
            let barHeight = minHeight + clamped * (maxHeight - minHeight)
            let rect = CGRect(
                x: originX + CGFloat(index) * (barWidth + barSpacing),
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: barWidth / 2,
                cornerHeight: barWidth / 2,
                transform: nil
            )

            let isPlayed = Double(index + 1) / Double(max(count, 1)) <= progress
            if isPlayed {
                playedPath.addPath(path)
            } else {
                remainingPath.addPath(path)
            }
        }

        playedLayer.path = playedPath
        remainingLayer.path = remainingPath
        playedLayer.fillColor = (isActive
            ? NSColor.labelColor.withAlphaComponent(0.95)
            : NSColor.labelColor.withAlphaComponent(0.8)).cgColor
        remainingLayer.fillColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        remainingLayer.contentsScale = scale
        playedLayer.contentsScale = scale
    }
}
