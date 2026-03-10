import AppKit
import Combine
import SwiftUI

enum TTSMiniPlayerMetrics {
    static let width: CGFloat = 290
    static let height: CGFloat = 40
    static let topOffset: CGFloat = 52
    static let waveformWidth: CGFloat = 80
    static let trailingActionsMinSpacing: CGFloat = 18
    static let horizontalPadding: CGFloat = 14
    static let trailingControlsPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6
}

struct TTSMiniPlayerView: NSViewRepresentable {
    let manager: TextToSpeechPlaybackManager
    let onNavigate: ((UUID) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, onNavigate: onNavigate)
    }

    func makeNSView(context: Context) -> TTSMiniPlayerNativeView {
        let view = TTSMiniPlayerNativeView()
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ nsView: TTSMiniPlayerNativeView, context: Context) {
        context.coordinator.update(manager: manager, onNavigate: onNavigate, view: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TTSMiniPlayerNativeView, context: Context) -> CGSize? {
        CGSize(width: TTSMiniPlayerMetrics.width, height: TTSMiniPlayerMetrics.height)
    }
}

extension TTSMiniPlayerView {
    @MainActor
    final class Coordinator {
        private var manager: TextToSpeechPlaybackManager
        private var onNavigate: ((UUID) -> Void)?
        private weak var view: TTSMiniPlayerNativeView?
        private var cancellables: Set<AnyCancellable> = []

        init(manager: TextToSpeechPlaybackManager, onNavigate: ((UUID) -> Void)?) {
            self.manager = manager
            self.onNavigate = onNavigate
        }

        func attach(_ view: TTSMiniPlayerNativeView) {
            self.view = view
            configureCallbacks()
            bind()
            applySnapshot()
        }

        func update(
            manager: TextToSpeechPlaybackManager,
            onNavigate: ((UUID) -> Void)?,
            view: TTSMiniPlayerNativeView
        ) {
            self.view = view
            self.onNavigate = onNavigate

            if self.manager !== manager {
                self.manager = manager
                bind()
            }

            configureCallbacks()
            applySnapshot()
        }

        private func bind() {
            cancellables.removeAll()

            manager.$state
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            manager.$playbackContext
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            let miniPlayerState = manager.miniPlayerState
            miniPlayerState.$waveformPeaks
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            miniPlayerState.$clipProgress
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            miniPlayerState.$clipCurrentTime
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)

            miniPlayerState.$clipDuration
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applySnapshot() }
                .store(in: &cancellables)
        }

        private func configureCallbacks() {
            view?.onPrimaryAction = { [weak self] in
                self?.handlePrimaryAction()
            }
            view?.onNavigate = { [weak self] in
                self?.handleNavigate()
            }
            view?.onStop = { [weak self] in
                self?.manager.stop()
            }
        }

        private func handlePrimaryAction() {
            guard let messageID = activeMessageID else { return }

            if case .playing = manager.state {
                manager.pause(messageID: messageID)
            } else if case .paused = manager.state {
                manager.resume(messageID: messageID)
            }
        }

        private func handleNavigate() {
            guard let context = manager.playbackContext else { return }
            onNavigate?(context.conversationID)
        }

        private var activeMessageID: UUID? {
            switch manager.state {
            case .generating(let id), .playing(let id), .paused(let id):
                return id
            case .idle:
                return nil
            }
        }

        private func applySnapshot() {
            view?.apply(snapshot: snapshot)
        }

        private var snapshot: TTSMiniPlayerSnapshot {
            let state = manager.state
            let miniPlayerState = manager.miniPlayerState
            let isGenerating: Bool
            let isPlaying: Bool
            let isPaused: Bool

            switch state {
            case .generating:
                isGenerating = true
                isPlaying = false
                isPaused = false
            case .playing:
                isGenerating = false
                isPlaying = true
                isPaused = false
            case .paused:
                isGenerating = false
                isPlaying = false
                isPaused = true
            case .idle:
                isGenerating = false
                isPlaying = false
                isPaused = false
            }

            let title = manager.playbackContext?.conversationTitle ?? "Text to Speech"
            let hasWaveform = miniPlayerState.waveformPeaks.contains { $0 > 0.001 }

            return TTSMiniPlayerSnapshot(
                title: title,
                timeText: formattedTime(miniPlayerState.clipCurrentTime),
                waveformPeaks: miniPlayerState.waveformPeaks,
                progress: miniPlayerState.clipProgress,
                isGenerating: isGenerating,
                isPlaying: isPlaying,
                isPaused: isPaused,
                showsPrimarySpinner: isGenerating,
                showsWaveform: hasWaveform,
                showsWaveformSpinner: isGenerating && !hasWaveform,
                canNavigate: manager.playbackContext != nil && onNavigate != nil,
                navigateToolTip: manager.playbackContext.map { "Jump to \($0.conversationTitle)" }
            )
        }

        private func formattedTime(_ seconds: TimeInterval) -> String {
            let clamped = max(0, Int(seconds.rounded(.down)))
            let hours = clamped / 3600
            let minutes = (clamped % 3600) / 60
            let secs = clamped % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, secs)
            }

            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

private struct TTSMiniPlayerSnapshot {
    let title: String
    let timeText: String
    let waveformPeaks: [CGFloat]
    let progress: Double
    let isGenerating: Bool
    let isPlaying: Bool
    let isPaused: Bool
    let showsPrimarySpinner: Bool
    let showsWaveform: Bool
    let showsWaveformSpinner: Bool
    let canNavigate: Bool
    let navigateToolTip: String?
}

final class TTSMiniPlayerNativeView: NSView {
    var onPrimaryAction: (() -> Void)?
    var onNavigate: (() -> Void)?
    var onStop: (() -> Void)?

    private let contentStackView = NSStackView()
    private let trailingButtonsStackView = NSStackView()
    private let primaryContainer = NSView()
    private let primaryButton = NSButton()
    private let primarySpinner = NSProgressIndicator()
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let waveformContainer = NSView()
    private let waveformView = TTSWaveformLayerView()
    private let waveformSpinner = NSProgressIndicator()
    private let navigateButton = NSButton()
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: TTSMiniPlayerMetrics.width, height: TTSMiniPlayerMetrics.height)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    fileprivate func apply(snapshot: TTSMiniPlayerSnapshot) {
        toolTip = snapshot.title
        timeLabel.stringValue = snapshot.timeText
        let primaryActionLabel = snapshot.isPlaying ? "Pause playback" : "Resume playback"

        if snapshot.showsPrimarySpinner {
            primarySpinner.isHidden = false
            primarySpinner.startAnimation(nil)
            primaryButton.isHidden = true
        } else {
            primarySpinner.stopAnimation(nil)
            primarySpinner.isHidden = true
            primaryButton.isHidden = false
            primaryButton.image = symbolImage(
                name: snapshot.isPlaying ? "pause.fill" : "play.fill",
                pointSize: 13,
                weight: .bold,
                accessibilityDescription: primaryActionLabel
            )
            primaryButton.toolTip = primaryActionLabel
            primaryButton.setAccessibilityLabel(primaryActionLabel)
        }

        if snapshot.showsWaveformSpinner {
            waveformSpinner.isHidden = false
            waveformSpinner.startAnimation(nil)
            waveformView.isHidden = true
        } else {
            waveformSpinner.stopAnimation(nil)
            waveformSpinner.isHidden = true
            waveformView.isHidden = false
            waveformView.apply(
                levels: snapshot.waveformPeaks,
                progress: snapshot.progress,
                isActive: snapshot.isPlaying || snapshot.isPaused || snapshot.isGenerating
            )
        }

        updateNavigateButtonVisibility(canNavigate: snapshot.canNavigate)
        navigateButton.toolTip = snapshot.navigateToolTip
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        applyAppearance()

        contentStackView.orientation = .horizontal
        contentStackView.alignment = .centerY
        contentStackView.distribution = .fill
        contentStackView.spacing = JinSpacing.small
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        trailingButtonsStackView.orientation = .horizontal
        trailingButtonsStackView.alignment = .centerY
        trailingButtonsStackView.distribution = .fill
        trailingButtonsStackView.detachesHiddenViews = true
        trailingButtonsStackView.spacing = JinSpacing.xSmall
        trailingButtonsStackView.translatesAutoresizingMaskIntoConstraints = false

        setupPrimaryContainer()
        setupTimeLabel()
        setupWaveformContainer()
        setupButtons()

        contentStackView.addArrangedSubview(primaryContainer)
        contentStackView.addArrangedSubview(timeLabel)
        contentStackView.addArrangedSubview(waveformContainer)

        trailingButtonsStackView.addArrangedSubview(navigateButton)
        trailingButtonsStackView.addArrangedSubview(closeButton)

        for view in [primaryContainer, timeLabel, navigateButton, closeButton] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        waveformContainer.setContentHuggingPriority(.required, for: .horizontal)
        waveformContainer.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        trailingButtonsStackView.setContentHuggingPriority(.required, for: .horizontal)
        trailingButtonsStackView.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(contentStackView)
        addSubview(trailingButtonsStackView)

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TTSMiniPlayerMetrics.horizontalPadding),
            contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: TTSMiniPlayerMetrics.verticalPadding),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -TTSMiniPlayerMetrics.verticalPadding),

            trailingButtonsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TTSMiniPlayerMetrics.trailingControlsPadding),
            trailingButtonsStackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            contentStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingButtonsStackView.leadingAnchor,
                constant: -TTSMiniPlayerMetrics.trailingActionsMinSpacing
            )
        ])
    }

    private func setupPrimaryContainer() {
        primaryContainer.translatesAutoresizingMaskIntoConstraints = false
        primaryContainer.addSubview(primaryButton)
        primaryContainer.addSubview(primarySpinner)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.isBordered = false
        primaryButton.focusRingType = .none
        primaryButton.imagePosition = .imageOnly
        primaryButton.target = self
        primaryButton.action = #selector(handlePrimaryAction)
        primaryButton.contentTintColor = .labelColor

        primarySpinner.translatesAutoresizingMaskIntoConstraints = false
        primarySpinner.controlSize = .mini
        primarySpinner.style = .spinning
        primarySpinner.isDisplayedWhenStopped = false

        NSLayoutConstraint.activate([
            primaryContainer.widthAnchor.constraint(equalToConstant: 22),
            primaryContainer.heightAnchor.constraint(equalToConstant: 22),

            primaryButton.leadingAnchor.constraint(equalTo: primaryContainer.leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: primaryContainer.trailingAnchor),
            primaryButton.topAnchor.constraint(equalTo: primaryContainer.topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: primaryContainer.bottomAnchor),

            primarySpinner.centerXAnchor.constraint(equalTo: primaryContainer.centerXAnchor),
            primarySpinner.centerYAnchor.constraint(equalTo: primaryContainer.centerYAnchor)
        ])
    }

    private func setupTimeLabel() {
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .left
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private func setupWaveformContainer() {
        waveformContainer.translatesAutoresizingMaskIntoConstraints = false
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformSpinner.translatesAutoresizingMaskIntoConstraints = false
        waveformSpinner.controlSize = .mini
        waveformSpinner.style = .spinning
        waveformSpinner.isDisplayedWhenStopped = false

        waveformContainer.addSubview(waveformView)
        waveformContainer.addSubview(waveformSpinner)

        NSLayoutConstraint.activate([
            waveformContainer.widthAnchor.constraint(equalToConstant: TTSMiniPlayerMetrics.waveformWidth),
            waveformContainer.heightAnchor.constraint(equalToConstant: 24),

            waveformView.leadingAnchor.constraint(equalTo: waveformContainer.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: waveformContainer.trailingAnchor),
            waveformView.topAnchor.constraint(equalTo: waveformContainer.topAnchor),
            waveformView.bottomAnchor.constraint(equalTo: waveformContainer.bottomAnchor),

            waveformSpinner.centerXAnchor.constraint(equalTo: waveformContainer.centerXAnchor),
            waveformSpinner.centerYAnchor.constraint(equalTo: waveformContainer.centerYAnchor)
        ])
    }

    private func setupButtons() {
        configureAuxiliaryButton(
            navigateButton,
            symbol: "arrow.up.right",
            toolTip: "Jump to chat",
            accessibilityLabel: "Jump to chat",
            action: #selector(handleNavigate)
        )

        configureAuxiliaryButton(
            closeButton,
            symbol: "xmark",
            toolTip: "Stop playback",
            accessibilityLabel: "Stop playback",
            action: #selector(handleStop)
        )
    }

    private func configureAuxiliaryButton(
        _ button: NSButton,
        symbol: String,
        toolTip: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.image = symbolImage(
            name: symbol,
            pointSize: 11,
            weight: .semibold,
            accessibilityDescription: accessibilityLabel
        )
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func applyAppearance() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = JinStrokeWidth.hairline
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -6)
    }

    private func symbolImage(
        name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        accessibilityDescription: String
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
    }

    private func updateNavigateButtonVisibility(canNavigate: Bool) {
        let containsNavigateButton = trailingButtonsStackView.arrangedSubviews.contains(navigateButton)

        if canNavigate {
            if !containsNavigateButton {
                trailingButtonsStackView.insertArrangedSubview(navigateButton, at: 0)
            }
        } else if containsNavigateButton {
            trailingButtonsStackView.removeArrangedSubview(navigateButton)
            navigateButton.removeFromSuperview()
        }
    }

    @objc private func handlePrimaryAction() {
        onPrimaryAction?()
    }

    @objc private func handleNavigate() {
        onNavigate?()
    }

    @objc private func handleStop() {
        onStop?()
    }
}

private final class TTSWaveformLayerView: NSView {
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
