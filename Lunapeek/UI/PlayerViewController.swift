// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import AVFoundation
import MediaPlayer

final class PlayerViewController: UIViewController {
    private let url: URL
    private var playerEngine: PlayerEngine?
    private var avPlayer: AVPlayer?
    private var avPlayerLayer: AVPlayerLayer?
    private var proxyServer: HTTPProxyServer?
    private var timeObserver: Any?
    private var videoView: UIView!

    private var controlView: UIView!
    private var playButton: UIButton!
    private var closeButton: UIButton!
    private var progressBar: UISlider!
    private var timeLabel: UILabel!
    private var isControlsHidden = false
    private var controlsHideTimer: Timer?

    // Brightness & Volume
    private var brightnessButton: UIButton!
    private var volumeButton: UIButton!
    private var brightnessSliderView: UIView?
    private var volumeSliderView: UIView?

    // Gesture indicator
    private var gestureIndicatorView: UIView?
    private var gestureIndicatorTimer: Timer?

    // Hidden volume view for system volume control
    private var volumeView: MPVolumeView?

    private var isFullscreen: Bool {
        return view.bounds.width > view.bounds.height
    }

    // Debug log view
    private var debugTextView: UITextView!
    private var logEntries: [String] = []
    private var isDebugVisible = false

    init(url: URL, proxyServer: HTTPProxyServer? = nil) {
        self.url = url
        self.proxyServer = proxyServer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        controlsHideTimer?.invalidate()
        gestureIndicatorTimer?.invalidate()
        // Clear log handler to prevent callbacks to deallocated self
        LogManager.shared.handler = nil
        // Remove observer first (safe even if player is gone)
        if let observer = timeObserver {
            avPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        // Stop proxy server
        proxyServer?.stop()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        LogManager.shared.clear()
        LogManager.shared.handler = { [weak self] entry in
            DispatchQueue.main.async {
                guard let self else { return }
                self.logEntries.append(entry)
                if self.logEntries.count > 50 { self.logEntries.removeFirst() }
                self.debugTextView?.text = self.logEntries.joined(separator: "\n")
                self.debugTextView?.scrollToBottom()
            }
        }
        setupUI()
        setupPlayer()
        setupGestures()
    }

    private func log(_ message: String) {
        Lunapeek.debugLog("🎬 \(message)")
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }

    private func setupUI() {
        view.backgroundColor = .black

        // Video view
        videoView = UIView(frame: .zero)
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)

        // Debug log view (initially hidden)
        debugTextView = UITextView()
        debugTextView.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        debugTextView.textColor = .green
        debugTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        debugTextView.isEditable = false
        debugTextView.isSelectable = true
        debugTextView.translatesAutoresizingMaskIntoConstraints = false
        debugTextView.isHidden = true
        view.addSubview(debugTextView)

        // Control overlay
        controlView = UIView(frame: .zero)
        controlView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        controlView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlView)

        // Back button (top left)
        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(backButton)

        // Right top button (fullscreen or close)
        closeButton = UIButton(type: .system)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(rightTopButtonTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(closeButton)
        updateRightTopButton()

        // Debug button
        let debugButton = UIButton(type: .system)
        debugButton.setImage(UIImage(systemName: "ladybug"), for: .normal)
        debugButton.tintColor = .yellow
        debugButton.addTarget(self, action: #selector(toggleDebug), for: .touchUpInside)
        debugButton.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(debugButton)

        // Play button
        playButton = UIButton(type: .system)
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.titleLabel?.font = .systemFont(ofSize: 48)
        playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(playButton)

        // Bottom controls container
        let bottomControls = UIView()
        bottomControls.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(bottomControls)

        // Brightness button
        brightnessButton = UIButton(type: .system)
        brightnessButton.setImage(UIImage(systemName: "sun.max"), for: .normal)
        brightnessButton.tintColor = .white
        brightnessButton.addTarget(self, action: #selector(brightnessTapped), for: .touchUpInside)
        brightnessButton.translatesAutoresizingMaskIntoConstraints = false
        bottomControls.addSubview(brightnessButton)

        // Progress bar
        progressBar = UISlider()
        progressBar.minimumValue = 0
        progressBar.maximumValue = 100
        progressBar.value = 0
        progressBar.tintColor = .systemBlue
        progressBar.addTarget(self, action: #selector(progressChanged), for: .valueChanged)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        bottomControls.addSubview(progressBar)

        // Volume button
        volumeButton = UIButton(type: .system)
        volumeButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        volumeButton.tintColor = .white
        volumeButton.addTarget(self, action: #selector(volumeTapped), for: .touchUpInside)
        volumeButton.translatesAutoresizingMaskIntoConstraints = false
        bottomControls.addSubview(volumeButton)

        // Time label
        timeLabel = UILabel()
        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        timeLabel.text = "0:00 / 0:00"
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomControls.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            debugTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            debugTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            debugTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            debugTextView.heightAnchor.constraint(equalToConstant: 200),

            controlView.topAnchor.constraint(equalTo: view.topAnchor),
            controlView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            debugButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            debugButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            debugButton.widthAnchor.constraint(equalToConstant: 44),
            debugButton.heightAnchor.constraint(equalToConstant: 44),

            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 80),
            playButton.heightAnchor.constraint(equalToConstant: 80),

            bottomControls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomControls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            brightnessButton.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor),
            brightnessButton.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            brightnessButton.widthAnchor.constraint(equalToConstant: 44),
            brightnessButton.heightAnchor.constraint(equalToConstant: 44),

            progressBar.leadingAnchor.constraint(equalTo: brightnessButton.trailingAnchor, constant: 8),
            progressBar.trailingAnchor.constraint(equalTo: volumeButton.leadingAnchor, constant: -8),
            progressBar.topAnchor.constraint(equalTo: bottomControls.topAnchor),

            volumeButton.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor),
            volumeButton.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            volumeButton.widthAnchor.constraint(equalToConstant: 44),
            volumeButton.heightAnchor.constraint(equalToConstant: 44),

            timeLabel.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
            timeLabel.bottomAnchor.constraint(equalTo: bottomControls.bottomAnchor)
        ])

        // Start auto-hide timer
        resetControlsHideTimer()
    }

    private func updateRightTopButton() {
        if isFullscreen {
            closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        } else {
            closeButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateRightTopButton()
        }
    }

    @objc private func toggleDebug() {
        isDebugVisible.toggle()
        debugTextView.isHidden = !isDebugVisible
    }

    // MARK: - Auto-hide controls

    private func resetControlsHideTimer() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }

    private func hideControls() {
        guard !isControlsHidden else { return }
        isControlsHidden = true
        UIView.animate(withDuration: 0.3) {
            self.controlView.alpha = 0
        }
    }

    private func showControls() {
        isControlsHidden = false
        UIView.animate(withDuration: 0.3) {
            self.controlView.alpha = 1
        }
        resetControlsHideTimer()
    }

    // MARK: - Brightness & Volume

    private func dismissSliderPopups() {
        brightnessSliderView?.removeFromSuperview()
        brightnessSliderView = nil
        volumeSliderView?.removeFromSuperview()
        volumeSliderView = nil
    }

    @objc private func brightnessTapped() {
        resetControlsHideTimer()
        if brightnessSliderView != nil {
            brightnessSliderView?.removeFromSuperview()
            brightnessSliderView = nil
            return
        }

        dismissSliderPopups()

        let sliderView = createVerticalSlider(type: .brightness, value: Float(UIScreen.main.brightness), min: 0, max: 1) { [weak self] value in
            UIScreen.main.brightness = CGFloat(value)
            self?.updateBrightnessIcon(value: value)
            self?.showGestureIndicator(type: .brightness, value: CGFloat(value))
        }
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sliderView)
        brightnessSliderView = sliderView

        NSLayoutConstraint.activate([
            sliderView.centerXAnchor.constraint(equalTo: brightnessButton.centerXAnchor),
            sliderView.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -16),
            sliderView.widthAnchor.constraint(equalToConstant: 44),
            sliderView.heightAnchor.constraint(equalToConstant: 150)
        ])
    }

    @objc private func volumeTapped() {
        resetControlsHideTimer()
        if volumeSliderView != nil {
            volumeSliderView?.removeFromSuperview()
            volumeSliderView = nil
            return
        }

        dismissSliderPopups()

        // Get current volume from MPVolumeView slider
        let currentVolume: Float
        if let slider = volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider {
            currentVolume = slider.value
        } else {
            currentVolume = AVAudioSession.sharedInstance().outputVolume
        }

        let sliderView = createVerticalSlider(type: .volume, value: currentVolume, min: 0, max: 1) { [weak self] value in
            if let slider = self?.volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider {
                slider.value = value
            }
            self?.updateVolumeIcon(value: value)
            self?.showGestureIndicator(type: .volume, value: CGFloat(value))
        }
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sliderView)
        volumeSliderView = sliderView

        NSLayoutConstraint.activate([
            sliderView.centerXAnchor.constraint(equalTo: volumeButton.centerXAnchor),
            sliderView.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -16),
            sliderView.widthAnchor.constraint(equalToConstant: 44),
            sliderView.heightAnchor.constraint(equalToConstant: 150)
        ])
    }

    private func createVerticalSlider(type: GestureIndicatorType, value: Float, min: Float, max: Float, changed: @escaping (Float) -> Void) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        container.layer.cornerRadius = 22

        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        slider.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)
        slider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(slider)

        // Store the callback
        objc_setAssociatedObject(slider, &sliderCallbackKey, changed, .OBJC_ASSOCIATION_COPY_NONATOMIC)

        NSLayoutConstraint.activate([
            slider.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            slider.widthAnchor.constraint(equalTo: container.heightAnchor, constant: -20)
        ])

        return container
    }

    private var sliderCallbackKey: UInt8 = 0

    @objc private func sliderValueChanged(_ slider: UISlider) {
        if let callback = objc_getAssociatedObject(slider, &sliderCallbackKey) as? (Float) -> Void {
            callback(slider.value)
        }
    }

    private func updateBrightnessIcon(value: Float) {
        let icon: String
        switch value {
        case 0..<0.3: icon = "sun.min"
        case 0.3..<0.7: icon = "sun.max"
        default: icon = "sun.max.fill"
        }
        brightnessButton.setImage(UIImage(systemName: icon), for: .normal)
    }

    private func updateVolumeIcon(value: Float) {
        let icon: String
        switch value {
        case 0: icon = "speaker.slash"
        case 0..<0.3: icon = "speaker.wave.1"
        case 0.3..<0.7: icon = "speaker.wave.2"
        default: icon = "speaker.wave.3"
        }
        volumeButton.setImage(UIImage(systemName: icon), for: .normal)
    }

    // MARK: - Navigation

    @objc private func backTapped() {
        resetControlsHideTimer()
        if isFullscreen {
            // Exit fullscreen
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        } else {
            // Exit player
            closeTapped()
        }
    }

    @objc private func rightTopButtonTapped() {
        resetControlsHideTimer()
        if isFullscreen {
            // Close
            closeTapped()
        } else {
            // Enter fullscreen
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
    }

    private func setupPlayer() {
        log("URL: \(url.absoluteString)")
        log("Extension: \(url.pathExtension)")

        // Check if URL is HTTP - use AVPlayer directly
        if url.scheme == "http" || url.scheme == "https" {
            log("Using AVPlayer for HTTP URL")
            setupAVPlayer()
            return
        }

        // Local file - use custom PlayerEngine
        let demuxer = DemuxerFactory.createDemuxer(for: url)
        log("Demuxer: \(type(of: demuxer))")

        let videoDecoder = VideoToolboxDecoderPlugin()
        let audioDecoder = AudioToolboxDecoderPlugin()
        let videoRenderer = VideoRenderer()
        let audioRenderer = AudioRenderer()

        playerEngine = PlayerEngine(
            demuxer: demuxer,
            videoDecoder: videoDecoder,
            audioDecoder: audioDecoder,
            videoRenderer: videoRenderer,
            audioRenderer: audioRenderer
        )

        videoView.layer.addSublayer(videoRenderer.layer)
        videoRenderer.layer.frame = videoView.bounds

        Task {
            do {
                log("Loading asset...")
                try await playerEngine?.load(url: url)
                log("✅ Loaded successfully")
                activateAudioSession()
                playerEngine?.play()
                updatePlayButton()
            } catch {
                log("❌ Error: \(error)")
                showError(error)
            }
        }
    }

    private func setupAVPlayer() {
        let player = AVPlayer(url: url)
        avPlayer = player

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = videoView.bounds
        playerLayer.videoGravity = .resizeAspect
        videoView.layer.addSublayer(playerLayer)
        avPlayerLayer = playerLayer

        // Add time observer for progress updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgress()
        }

        activateAudioSession()
        player.play()
        log("✅ AVPlayer started")

        // Update play button state
        playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)

        // Update progress initially
        updateProgress()
    }

    private func activateAudioSession() {
        Task.detached(priority: .userInitiated) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                print("Failed to activate audio session: \(error)")
            }
        }
    }

    private func deactivateAudioSession() {
        Task.detached(priority: .background) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
        }
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleAspect))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        // Swipe gestures for brightness (left half) and volume (right half)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panGesture)

        // Setup hidden volume view for system volume control
        setupVolumeView()
    }

    private func setupVolumeView() {
        // Create hidden volume view to control system volume
        volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 100, height: 100))
        volumeView?.alpha = 0.01
        view.addSubview(volumeView!)
    }

    @objc private func toggleControls() {
        // Dismiss any slider popups first
        if brightnessSliderView != nil || volumeSliderView != nil {
            dismissSliderPopups()
            return
        }

        if isControlsHidden {
            showControls()
        } else {
            hideControls()
        }
    }

    // MARK: - Pan Gesture for Brightness/Volume

    private var initialPanY: CGFloat = 0
    private var isAdjustingBrightness = false

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            initialPanY = location.y
            isAdjustingBrightness = location.x < view.bounds.width / 2

        case .changed:
            // Calculate change based on initial position
            let deltaY = initialPanY - location.y
            let sensitivity: CGFloat = 300 // pixels for full range
            let change = deltaY / sensitivity

            if isAdjustingBrightness {
                let newBrightness = max(0, min(1, UIScreen.main.brightness + change * 0.1))
                UIScreen.main.brightness = newBrightness
                showGestureIndicator(type: .brightness, value: newBrightness)
            } else {
                // Volume: get current volume from slider
                if let slider = volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider {
                    let newVolume = max(0, min(1, slider.value + Float(change * 0.1)))
                    slider.value = newVolume
                    showGestureIndicator(type: .volume, value: CGFloat(newVolume))
                }
            }

            // Update initial for next iteration
            initialPanY = location.y

        case .ended, .cancelled:
            // Keep indicator visible for a moment then hide
            break

        default:
            break
        }
    }

    private enum GestureIndicatorType {
        case brightness
        case volume
    }

    private func showGestureIndicator(type: GestureIndicatorType, value: CGFloat) {
        // Remove existing indicator
        gestureIndicatorView?.removeFromSuperview()
        gestureIndicatorTimer?.invalidate()

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let icon = UIImageView()
        let iconName: String
        switch type {
        case .brightness:
            iconName = value < 0.3 ? "sun.min" : (value < 0.7 ? "sun.max" : "sun.max.fill")
        case .volume:
            iconName = value < 0.01 ? "speaker.slash" : (value < 0.3 ? "speaker.wave.1" : (value < 0.7 ? "speaker.wave.2" : "speaker.wave.3"))
        }
        icon.image = UIImage(systemName: iconName)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        let label = UILabel()
        label.text = "\(Int(value * 100))%"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 80),
            container.heightAnchor.constraint(equalToConstant: 80),

            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),

            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        gestureIndicatorView = container

        // Hide after 1 second
        gestureIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3, animations: {
                self?.gestureIndicatorView?.alpha = 0
            }) { _ in
                self?.gestureIndicatorView?.removeFromSuperview()
                self?.gestureIndicatorView = nil
            }
        }
    }

    @objc private func toggleAspect() {
        // TODO: Toggle between fit and fill
    }

    @objc private func closeTapped() {
        // Cleanup must happen on main thread for AVPlayer
        if let observer = timeObserver {
            avPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        avPlayer?.pause()
        avPlayer = nil
        avPlayerLayer?.removeFromSuperlayer()
        avPlayerLayer = nil
        proxyServer?.stop()
        proxyServer = nil
        deactivateAudioSession()

        Task { [weak self] in
            await self?.playerEngine?.stop()
            await MainActor.run {
                self?.dismiss(animated: true)
            }
        }
    }

    @objc private func playPauseTapped() {
        resetControlsHideTimer()

        // Handle AVPlayer
        if let player = avPlayer {
            if player.timeControlStatus == .playing {
                player.pause()
                playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            } else {
                player.play()
                playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            }
            return
        }

        // Handle PlayerEngine
        guard let engine = playerEngine else { return }

        switch engine.state {
        case .ready, .paused:
            engine.play()
        case .playing:
            engine.pause()
        default:
            break
        }
        updatePlayButton()
    }

    @objc private func progressChanged() {
        guard let player = avPlayer else { return }

        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration > 0 else { return }

        let targetTime = duration * Double(progressBar.value) / 100
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player.seek(to: cmTime)
    }

    private func updateProgress() {
        guard let player = avPlayer else { return }

        let currentTime = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0

        if duration > 0 {
            let progress = (currentTime / duration) * 100
            progressBar.value = Float(progress)

            let currentStr = formatTime(currentTime)
            let durationStr = formatTime(duration)
            timeLabel.text = "\(currentStr) / \(durationStr)"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func updatePlayButton() {
        let imageName: String
        if playerEngine?.state == .playing {
            imageName = "pause.fill"
        } else {
            imageName = "play.fill"
        }
        playButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    private func showError(_ error: Error) {
        var message = error.localizedDescription
        if let demuxerError = error as? DemuxerError {
            switch demuxerError {
            case .failedToLoadTracks:
                message = "Failed to load video tracks"
            case .failedToStartReading(let innerError):
                message = "Failed to start reading: \(innerError?.localizedDescription ?? "unknown")"
            case .readerError(let innerError):
                message = "Reader error: \(innerError?.localizedDescription ?? "unknown")"
            case .noAsset:
                message = "No asset loaded"
            }
        }

        // Show error and force show debug log
        isDebugVisible = true
        debugTextView.isHidden = false

        let alert = UIAlertController(
            title: "Playback Error",
            message: message + "\n\nSee debug log above for details",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerEngine?.videoRendererLayer?.frame = videoView.bounds
        avPlayerLayer?.frame = videoView.bounds
    }
}

extension UITextView {
    func scrollToBottom() {
        let range = NSMakeRange(text.count - 1, 1)
        scrollRangeToVisible(range)
    }
}
