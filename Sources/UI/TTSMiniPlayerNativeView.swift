import AppKit

final class TTSMiniPlayerNativeView: NSView {
    var onPrimaryAction: (() -> Void)?
    var onNavigate: (() -> Void)?
    var onStop: (() -> Void)?

    private let contentStackView = NSStackView()
    private let trailingButtonsStackView = NSStackView()
    private let primaryContainer = NSView()
    private let primaryButton = NSButton()
    private let primaryOrb = JinActivityOrbNSView()
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let waveformContainer = NSView()
    private let waveformView = TTSWaveformLayerView()
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

    func apply(snapshot: TTSMiniPlayerSnapshot) {
        toolTip = snapshot.title
        timeLabel.stringValue = snapshot.timeText
        let primaryActionLabel = snapshot.isPlaying ? "Pause playback" : "Resume playback"

        if snapshot.showsPrimarySpinner {
            primaryOrb.isHidden = false
            primaryOrb.apply(
                kind: .composing,
                size: .inline,
                paused: false,
                isDark: drawsAsDark
            )
            primaryButton.isHidden = true
        } else {
            primaryOrb.apply(
                kind: .composing,
                size: .inline,
                paused: true,
                isDark: drawsAsDark
            )
            primaryOrb.isHidden = true
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

        waveformView.isHidden = false
        waveformView.apply(
            levels: snapshot.waveformPeaks,
            progress: snapshot.progress,
            isActive: snapshot.isPlaying || snapshot.isPaused || snapshot.isGenerating
        )

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
        primaryContainer.addSubview(primaryOrb)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.isBordered = false
        primaryButton.focusRingType = .none
        primaryButton.imagePosition = .imageOnly
        primaryButton.target = self
        primaryButton.action = #selector(handlePrimaryAction)
        primaryButton.contentTintColor = .labelColor

        primaryOrb.translatesAutoresizingMaskIntoConstraints = false
        primaryOrb.isHidden = true

        NSLayoutConstraint.activate([
            primaryContainer.widthAnchor.constraint(equalToConstant: 22),
            primaryContainer.heightAnchor.constraint(equalToConstant: 22),

            primaryButton.leadingAnchor.constraint(equalTo: primaryContainer.leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: primaryContainer.trailingAnchor),
            primaryButton.topAnchor.constraint(equalTo: primaryContainer.topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: primaryContainer.bottomAnchor),

            primaryOrb.centerXAnchor.constraint(equalTo: primaryContainer.centerXAnchor),
            primaryOrb.centerYAnchor.constraint(equalTo: primaryContainer.centerYAnchor),
            primaryOrb.widthAnchor.constraint(equalToConstant: 20),
            primaryOrb.heightAnchor.constraint(equalToConstant: 20)
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

        waveformContainer.addSubview(waveformView)

        NSLayoutConstraint.activate([
            waveformContainer.widthAnchor.constraint(equalToConstant: TTSMiniPlayerMetrics.waveformWidth),
            waveformContainer.heightAnchor.constraint(equalToConstant: 24),

            waveformView.leadingAnchor.constraint(equalTo: waveformContainer.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: waveformContainer.trailingAnchor),
            waveformView.topAnchor.constraint(equalTo: waveformContainer.topAnchor),
            waveformView.bottomAnchor.constraint(equalTo: waveformContainer.bottomAnchor)
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
        // Resolve token colors against this view's appearance so the cached
        // CGColors stay correct when the user toggles light/dark or when the
        // host window uses an overridden appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(JinSemanticColor.raisedSurface).cgColor
            layer?.borderColor = NSColor(JinSemanticColor.borderSubtle).cgColor
            layer?.shadowColor = NSColor(JinSemanticColor.shadowElevated).cgColor
        }
        layer?.borderWidth = JinStrokeWidth.hairline
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        if !primaryOrb.isHidden {
            primaryOrb.apply(
                kind: .composing,
                size: .inline,
                paused: false,
                isDark: drawsAsDark
            )
        }
    }

    private var drawsAsDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
