// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import AVFoundation
import AVKit
import MediaPlayer
import ActivityKit
import ActivityKit

final class PlayerViewController: UIViewController {
    private let url: URL
    private var playerEngine: PlayerEngine?
    private var avQueuePlayer: AVQueuePlayer?
    private var avPlayerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var proxyServer: HTTPProxyServer?
    private var timeObserver: Any?
    private var videoView: UIView!

    // Live Activity
    private var currentActivity: Activity<LunapeekWidgetAttributes>?

    private var controlView: UIView!
    private var playButton: UIButton!
    private var closeButton: UIButton!
    private var progressBar: UISlider!
    private var timeLabel: UILabel!
    private var isControlsHidden = false
    private var controlsHideTimer: Timer?

    // Control buttons
    private var brightnessButton: UIButton!
    private var volumeButton: UIButton!
    private var speedButton: UIButton!
    private var lockButton: UIButton!
    private var previousButton: UIButton!
    private var nextButton: UIButton!
    private var backwardButton: UIButton!
    private var forwardButton: UIButton!
    private var centerUnlockButton: UIButton!
    private var centerPlayButton: UIButton!
    private var brightnessSliderView: UIView?
    private var volumeSliderView: UIView?
    private var speedPopupView: UIView?

    // Lock state
    private var isLocked = false

    // Pause state (for center play button)
    private var isPaused = false

    // Current playback rate
    private var currentRate: Float = 1.0
    private let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // Gesture indicator
    private var gestureIndicatorView: UIView?
    private var gestureIndicatorTimer: Timer?

    // Hidden volume view for system volume control
    private var volumeView: MPVolumeView?

    // Volume tracking
    private var lastVolume: Float = 0.5

    // Playlist
    private var playlist: [URL]?
    private var currentIndex: Int = 0

    private var isFullscreen: Bool {
        return isFullscreenMode
    }

    // Debug log view
    private var debugTextView: UITextView!
    private var logEntries: [String] = []
    private var isDebugVisible = false

    init(url: URL, proxyServer: HTTPProxyServer? = nil, playlist: [URL]? = nil, currentIndex: Int = 0) {
        self.url = url
        self.proxyServer = proxyServer
        self.playlist = playlist
        self.currentIndex = currentIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        controlsHideTimer?.invalidate()
        gestureIndicatorTimer?.invalidate()
        seekIndicatorTimer?.invalidate()
        // Clear log handler to prevent callbacks to deallocated self
        LogManager.shared.handler = nil
        // Remove observer first (safe even if player is gone)
        if let observer = timeObserver {
            avQueuePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        // Stop proxy server
        proxyServer?.stop()
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
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
        setupVolumeObservation()
        setupAppLifecycleObservers()
    }

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appWillResignActive() {
        // For pause mode, just pause (no PiP since pipController is not created)
        guard avQueuePlayer != nil else { return }
        guard Settings.shared.exitBehavior == .pause else { return }

        avQueuePlayer?.pause()
        isPaused = true
        setPlayButtonIcon(isPlaying: false)
        updateCenterButtons()
    }

    @objc private func appDidEnterBackground() {
        guard avQueuePlayer != nil else { return }

        let exitBehavior = Settings.shared.exitBehavior
        switch exitBehavior {
        case .pip:
            // Start Picture in Picture
            if let pip = pipController, pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
            }
        case .background:
            // Remove player layer to allow background audio playback
            avPlayerLayer?.removeFromSuperlayer()
            avPlayerLayer = nil
            // Ensure audio session is active for background playback
            try? AVAudioSession.sharedInstance().setActive(true)
            // Ensure now playing info is current for Dynamic Island
            updateNowPlayingInfo()
        case .pause:
            // Already paused in willResignActive
            break
        }
    }

    @objc private func appWillEnterForeground() {
        // Stop PiP when returning to app (only if pipController exists)
        if let pip = pipController, pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }

        // Restore player layer for background mode
        if Settings.shared.exitBehavior == .background, avPlayerLayer == nil, let player = avQueuePlayer {
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = videoView.bounds
            playerLayer.videoGravity = Settings.shared.defaultAspectRatio.videoGravity
            videoView.layer.addSublayer(playerLayer)
            avPlayerLayer = playerLayer
        }

        // Update button state for pause mode
        if Settings.shared.exitBehavior == .pause {
            setPlayButtonIcon(isPlaying: false)
            updateCenterButtons()
        }
    }

    private func setupVolumeObservation() {
        // Create MPVolumeView for volume control
        if volumeView == nil {
            volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 100, height: 100))
            volumeView?.alpha = 0.01
            view.addSubview(volumeView!)
        }

        // Find the slider inside MPVolumeView and observe its value changes
        // This works for both hardware button presses and programmatic changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let slider = self?.volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider {
                slider.addTarget(self, action: #selector(self?.volumeSliderChanged(_:)), for: .valueChanged)
                self?.lastVolume = slider.value
            }
        }
    }

    @objc private func volumeSliderChanged(_ sender: UISlider) {
        // Show custom indicator when volume changes (from hardware buttons or swipe)
        let newVolume = sender.value
        if newVolume != lastVolume {
            lastVolume = newVolume
            showGestureIndicator(type: .volume, value: CGFloat(newVolume))
        }
    }

    @objc private func volumeChanged(notification: Notification) {
        // Fallback: Get volume from notification
        if let volume = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float {
            lastVolume = volume
            showGestureIndicator(type: .volume, value: CGFloat(volume))
        }
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

        // Center unlock button (visible only when locked)
        centerUnlockButton = UIButton(type: .system)
        centerUnlockButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
        centerUnlockButton.tintColor = .white
        centerUnlockButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        centerUnlockButton.layer.cornerRadius = 30
        centerUnlockButton.addTarget(self, action: #selector(centerUnlockTapped), for: .touchUpInside)
        centerUnlockButton.translatesAutoresizingMaskIntoConstraints = false
        centerUnlockButton.isHidden = true
        view.addSubview(centerUnlockButton)

        // Center play button (visible when paused)
        centerPlayButton = UIButton(type: .system)
        let centerPlayImage = UIImage(systemName: "play.fill")?
            .applyingSymbolConfiguration(.init(pointSize: 36, weight: .bold, scale: .large))
        centerPlayButton.setImage(centerPlayImage, for: .normal)
        centerPlayButton.tintColor = .white
        centerPlayButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        centerPlayButton.layer.cornerRadius = 35
        centerPlayButton.addTarget(self, action: #selector(centerPlayTapped), for: .touchUpInside)
        centerPlayButton.translatesAutoresizingMaskIntoConstraints = false
        centerPlayButton.isHidden = true
        view.addSubview(centerPlayButton)

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

        // Bottom controls container
        let bottomControls = UIView()
        bottomControls.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(bottomControls)

        // Brightness button (left of progress bar)
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

        // Volume button (right of progress bar)
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

        // Button row container
        let buttonRow = UIView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        bottomControls.addSubview(buttonRow)

        // Speed button (far left)
        speedButton = UIButton(type: .system)
        speedButton.setTitle("1x", for: .normal)
        speedButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        speedButton.tintColor = .white
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(speedButton)

        // Previous button
        previousButton = UIButton(type: .system)
        previousButton.setImage(UIImage(systemName: "backward.end.fill"), for: .normal)
        previousButton.tintColor = .white
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(previousButton)

        // Backward button (10s)
        backwardButton = UIButton(type: .system)
        backwardButton.setImage(UIImage(systemName: "gobackward.10"), for: .normal)
        backwardButton.tintColor = .white
        backwardButton.addTarget(self, action: #selector(backwardTapped), for: .touchUpInside)
        backwardButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(backwardButton)

        // Play/Pause button (center, largest)
        playButton = UIButton(type: .system)
        let pauseImage = UIImage(systemName: "pause.fill")?
            .applyingSymbolConfiguration(.init(pointSize: 36, weight: .bold, scale: .large))
        playButton.setImage(pauseImage, for: .normal)
        playButton.tintColor = .white
        playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(playButton)

        // Forward button (10s)
        forwardButton = UIButton(type: .system)
        forwardButton.setImage(UIImage(systemName: "goforward.10"), for: .normal)
        forwardButton.tintColor = .white
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(forwardButton)

        // Next button
        nextButton = UIButton(type: .system)
        nextButton.setImage(UIImage(systemName: "forward.end.fill"), for: .normal)
        nextButton.tintColor = .white
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(nextButton)

        // Lock button (far right)
        lockButton = UIButton(type: .system)
        lockButton.setImage(UIImage(systemName: "lock.open"), for: .normal)
        lockButton.tintColor = .white
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(lockButton)

        // Update prev/next button states
        updateNavigationButtons()

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

            centerUnlockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerUnlockButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            centerUnlockButton.widthAnchor.constraint(equalToConstant: 60),
            centerUnlockButton.heightAnchor.constraint(equalToConstant: 60),

            centerPlayButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerPlayButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            centerPlayButton.widthAnchor.constraint(equalToConstant: 70),
            centerPlayButton.heightAnchor.constraint(equalToConstant: 70),

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

            // Bottom controls
            bottomControls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomControls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // Progress bar row
            brightnessButton.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor),
            brightnessButton.topAnchor.constraint(equalTo: bottomControls.topAnchor),
            brightnessButton.widthAnchor.constraint(equalToConstant: 44),
            brightnessButton.heightAnchor.constraint(equalToConstant: 44),

            progressBar.leadingAnchor.constraint(equalTo: brightnessButton.trailingAnchor, constant: 8),
            progressBar.trailingAnchor.constraint(equalTo: volumeButton.leadingAnchor, constant: -8),
            progressBar.centerYAnchor.constraint(equalTo: brightnessButton.centerYAnchor),

            volumeButton.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor),
            volumeButton.topAnchor.constraint(equalTo: bottomControls.topAnchor),
            volumeButton.widthAnchor.constraint(equalToConstant: 44),
            volumeButton.heightAnchor.constraint(equalToConstant: 44),

            // Time label
            timeLabel.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),

            // Button row (below time label)
            buttonRow.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor),
            buttonRow.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 8),
            buttonRow.heightAnchor.constraint(equalToConstant: 50),
            buttonRow.bottomAnchor.constraint(equalTo: bottomControls.bottomAnchor),

            // Speed (far left)
            speedButton.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
            speedButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            speedButton.widthAnchor.constraint(equalToConstant: 40),
            speedButton.heightAnchor.constraint(equalToConstant: 36),

            // Previous
            previousButton.leadingAnchor.constraint(equalTo: speedButton.trailingAnchor, constant: 4),
            previousButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 36),
            previousButton.heightAnchor.constraint(equalToConstant: 36),

            // Backward
            backwardButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -8),
            backwardButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            backwardButton.widthAnchor.constraint(equalToConstant: 36),
            backwardButton.heightAnchor.constraint(equalToConstant: 36),

            // Play button (center, largest)
            playButton.centerXAnchor.constraint(equalTo: buttonRow.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 70),
            playButton.heightAnchor.constraint(equalToConstant: 70),

            // Forward
            forwardButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 8),
            forwardButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 36),
            forwardButton.heightAnchor.constraint(equalToConstant: 36),

            // Next
            nextButton.trailingAnchor.constraint(equalTo: lockButton.leadingAnchor, constant: -4),
            nextButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36),

            // Lock (far right)
            lockButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
            lockButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 32),
            lockButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        // Show controls initially
        showControls()
    }

    private func updateRightTopButton() {
        if isFullscreen {
            closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        } else {
            closeButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        }
    }

    @objc private func toggleDebug() {
        isDebugVisible.toggle()
        debugTextView.isHidden = !isDebugVisible
    }

    // MARK: - Auto-hide controls

    private func resetControlsHideTimer() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }

    private func hideControls() {
        guard !isControlsHidden else { return }
        // Dismiss any slider popups before hiding controls
        dismissSliderPopups()
        speedPopupView?.removeFromSuperview()
        speedPopupView = nil
        isControlsHidden = true
        UIView.animate(withDuration: 0.3) {
            self.controlView.alpha = 0
            self.centerPlayButton.alpha = 0
        }
    }

    private func showControls() {
        isControlsHidden = false
        updateCenterButtons()
        UIView.animate(withDuration: 0.3) {
            self.controlView.alpha = 1
            if !self.isLocked {
                self.centerPlayButton.alpha = 1
            }
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
        controlView.addSubview(sliderView)
        brightnessSliderView = sliderView

        NSLayoutConstraint.activate([
            sliderView.leadingAnchor.constraint(equalTo: brightnessButton.leadingAnchor),
            sliderView.bottomAnchor.constraint(equalTo: brightnessButton.topAnchor, constant: -16),
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
        controlView.addSubview(sliderView)
        volumeSliderView = sliderView

        NSLayoutConstraint.activate([
            sliderView.trailingAnchor.constraint(equalTo: volumeButton.trailingAnchor),
            sliderView.bottomAnchor.constraint(equalTo: volumeButton.topAnchor, constant: -16),
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

    // MARK: - Control Buttons

    private func updateNavigationButtons() {
        let hasPrev = playlist != nil && currentIndex > 0
        let hasNext = playlist != nil && currentIndex < (playlist?.count ?? 1) - 1

        previousButton.isEnabled = hasPrev
        previousButton.alpha = hasPrev ? 1.0 : 0.3
        nextButton.isEnabled = hasNext
        nextButton.alpha = hasNext ? 1.0 : 0.3
    }

    @objc private func previousTapped() {
        resetControlsHideTimer()
        guard let playlist = playlist, currentIndex > 0 else { return }
        let newIndex = currentIndex - 1
        let newUrl = playlist[newIndex]
        currentIndex = newIndex
        playFile(at: newUrl)
        updateNavigationButtons()
    }

    @objc private func nextTapped() {
        resetControlsHideTimer()
        guard let playlist = playlist, currentIndex < playlist.count - 1 else { return }
        let newIndex = currentIndex + 1
        let newUrl = playlist[newIndex]
        currentIndex = newIndex
        playFile(at: newUrl)
        updateNavigationButtons()
    }

    @objc private func backwardTapped() {
        resetControlsHideTimer()
        guard let player = avQueuePlayer else { return }
        let currentTime = player.currentTime().seconds
        let newTime = max(0, currentTime - 10)
        let time = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: time)
    }

    @objc private func forwardTapped() {
        resetControlsHideTimer()
        guard let player = avQueuePlayer else { return }
        let currentTime = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        let newTime = min(duration, currentTime + 10)
        let time = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: time)
    }

    @objc private func speedTapped() {
        resetControlsHideTimer()
        if speedPopupView != nil {
            speedPopupView?.removeFromSuperview()
            speedPopupView = nil
            return
        }

        let popup = UIView()
        popup.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        popup.layer.cornerRadius = 12
        popup.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(popup)
        speedPopupView = popup

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        popup.addSubview(stack)

        for rate in availableRates {
            let button = UIButton(type: .system)
            button.setTitle("\(rate == 1.0 ? "1x" : "\(rate)x")", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: rate == currentRate ? .bold : .regular)
            button.tintColor = rate == currentRate ? .systemBlue : .white
            button.tag = Int(rate * 100)
            button.addTarget(self, action: #selector(speedSelected(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: speedButton.leadingAnchor),
            popup.bottomAnchor.constraint(equalTo: speedButton.topAnchor, constant: -16),
            popup.widthAnchor.constraint(equalToConstant: 70),

            stack.topAnchor.constraint(equalTo: popup.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: popup.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: popup.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: popup.bottomAnchor, constant: -8)
        ])
    }

    @objc private func speedSelected(_ button: UIButton) {
        let rate = Float(button.tag) / 100.0
        currentRate = rate
        avQueuePlayer?.rate = rate
        speedButton.setTitle(rate == 1.0 ? "1x" : "\(rate)x", for: .normal)
        speedPopupView?.removeFromSuperview()
        speedPopupView = nil
    }

    @objc private func lockTapped() {
        isLocked.toggle()
        updateLockState()
    }

    @objc private func centerUnlockTapped() {
        isLocked = false
        updateLockState()
    }

    @objc private func centerPlayTapped() {
        resetControlsHideTimer()

        if let player = avQueuePlayer {
            if player.timeControlStatus == .playing {
                player.pause()
                isPaused = true
                setPlayButtonIcon(isPlaying: false)
            } else {
                player.play()
                if currentRate != 1.0 {
                    player.rate = currentRate
                }
                isPaused = false
                setPlayButtonIcon(isPlaying: true)
            }
            updateCenterButtons()
            return
        }

        // Handle PlayerEngine
        guard let engine = playerEngine else { return }

        switch engine.state {
        case .ready, .paused:
            engine.play()
            isPaused = false
            setPlayButtonIcon(isPlaying: true)
        case .playing:
            engine.pause()
            isPaused = true
            setPlayButtonIcon(isPlaying: false)
        default:
            break
        }
        updateCenterButtons()
    }

    private func updateLockState() {
        if isLocked {
            // Lock: hide controls, hide center play button, show center unlock button
            hideControls()
            centerPlayButton.isHidden = true
            centerUnlockButton.isHidden = false
            lockButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
            lockButton.tintColor = .systemBlue
        } else {
            // Unlock: show controls, hide center unlock button, show play button if paused
            centerUnlockButton.isHidden = true
            lockButton.setImage(UIImage(systemName: "lock.open"), for: .normal)
            lockButton.tintColor = .white
            showControls()
            updateCenterButtons()
        }
    }

    private func updateCenterButtons() {
        // Update center button icon based on play state
        let imageName = isPaused ? "play.fill" : "pause.fill"
        let image = UIImage(systemName: imageName)?
            .applyingSymbolConfiguration(.init(pointSize: 36, weight: .bold, scale: .large))
        centerPlayButton.setImage(image, for: .normal)

        // Show center button when controls are visible and not locked
        centerPlayButton.isHidden = isLocked || isControlsHidden
    }

    private func playFile(at url: URL) {
        log("▶️ playFile: \(url.lastPathComponent)")

        // Remove old time observer first
        if let observer = timeObserver {
            avQueuePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        // Stop and remove PlayerEngine if present
        if let engine = playerEngine {
            engine.videoRendererLayer?.removeFromSuperlayer()
            Task {
                await engine.stop()
            }
            playerEngine = nil
        }

        // Remove old player layer
        avPlayerLayer?.removeFromSuperlayer()
        avPlayerLayer = nil

        // Stop current player
        avQueuePlayer?.pause()
        avQueuePlayer = nil

        // Build queue from currentIndex (find index for the URL)
        var items: [AVPlayerItem] = []
        if let playlist = playlist {
            // Find the index of the URL in playlist
            if let idx = playlist.firstIndex(of: url) {
                currentIndex = idx
            }
            for i in currentIndex..<playlist.count {
                items.append(AVPlayerItem(url: playlist[i]))
            }
        } else {
            items.append(AVPlayerItem(url: url))
        }

        // Create new AVQueuePlayer with queue from current position
        let player = AVQueuePlayer(items: items)
        let shouldAutoPlay = Settings.shared.autoPlayNext
        player.actionAtItemEnd = shouldAutoPlay ? .advance : .pause
        avQueuePlayer = player

        // Only activate audio session, don't reconfigure in background
        let isInBackground = UIApplication.shared.applicationState == .background
        if isInBackground {
            log("📺 In background mode, just activate session")
            try? AVAudioSession.sharedInstance().setActive(true)
        } else {
            log("📺 In foreground, setup audio session")
            activateAudioSession()
        }

        // Only create player layer if app is in foreground
        if !isInBackground {
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = videoView.bounds
            playerLayer.videoGravity = Settings.shared.defaultAspectRatio.videoGravity
            videoView.layer.addSublayer(playerLayer)
            avPlayerLayer = playerLayer
            log("📺 Player layer created (foreground)")
        } else {
            log("📺 No player layer (background mode)")
        }

        // Setup time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateProgress()
        }

        // Observe end - use nil to receive all items
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        // Play and apply current playback rate
        player.play()
        if currentRate != 1.0 {
            player.rate = currentRate
        }
        log("▶️ Player started, rate=\(currentRate)")
        updatePlayButton()

        // Update progress and now playing info for Dynamic Island
        updateProgress()
        updateNowPlayingInfo()

        // Start Live Activity for Dynamic Island
        startLiveActivity()
    }

    // MARK: - Navigation

    @objc private func backTapped() {
        resetControlsHideTimer()
        if isFullscreen {
            // Exit fullscreen
            exitFullscreen()
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
            enterFullscreen()
        }
    }

    private var isFullscreenMode = false

    private func enterFullscreen() {
        isFullscreenMode = true
        updateRightTopButton()

        // Rotate to landscape by rotating the view
        let rotationAngle = CGFloat.pi / 2
        UIView.animate(withDuration: 0.3) {
            self.view.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.view.bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.height, height: UIScreen.main.bounds.width)
        }

        // Update video layer
        avPlayerLayer?.frame = videoView.bounds
        playerEngine?.videoRendererLayer?.frame = videoView.bounds
    }

    private func exitFullscreen() {
        isFullscreenMode = false
        updateRightTopButton()

        // Rotate back to portrait
        UIView.animate(withDuration: 0.3) {
            self.view.transform = .identity
            self.view.bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        }

        // Update video layer
        avPlayerLayer?.frame = videoView.bounds
        playerEngine?.videoRendererLayer?.frame = videoView.bounds
    }

    private func setupPlayer() {
        log("URL: \(url.absoluteString)")
        log("Extension: \(url.pathExtension)")

        // For all files, use AVPlayer (more stable for local files)
        if url.scheme == "http" || url.scheme == "https" || url.isFileURL {
            log("Using AVPlayer")
            setupAVPlayer()
            return
        }

        // Other protocols - use custom PlayerEngine (not commonly used)
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
                setPlayButtonIcon(isPlaying: true)
            } catch {
                log("❌ Error: \(error)")
                showError(error)
            }
        }
    }

    private func setupAVPlayer() {
        // Create player items starting from currentIndex
        var items: [AVPlayerItem] = []
        if let playlist = playlist {
            for i in currentIndex..<playlist.count {
                items.append(AVPlayerItem(url: playlist[i]))
            }
        } else {
            items.append(AVPlayerItem(url: url))
        }

        // Create AVQueuePlayer with items starting from current position
        let player = AVQueuePlayer(items: items)
        avQueuePlayer = player

        // We handle repeat/auto-play logic ourselves
        let shouldAutoPlay = Settings.shared.autoPlayNext
        player.actionAtItemEnd = shouldAutoPlay ? .advance : .pause

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = videoView.bounds
        playerLayer.videoGravity = Settings.shared.defaultAspectRatio.videoGravity
        videoView.layer.addSublayer(playerLayer)
        avPlayerLayer = playerLayer

        // Setup Picture in Picture (only if exit behavior is .pip)
        if Settings.shared.exitBehavior == .pip {
            if AVPictureInPictureController.isPictureInPictureSupported() {
                pipController = try? AVPictureInPictureController(playerLayer: playerLayer)
                pipController?.delegate = self
            }
        }

        // Add time observer for progress updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgress()
        }

        // Observe video end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        activateAudioSession()
        player.play()
        log("✅ AVQueuePlayer started with items")
        setPlayButtonIcon(isPlaying: true)

        // Update progress initially
        updateProgress()
    }

    @objc private func playerDidFinishPlaying() {
        log("🎬 Video finished, repeatMode=\(Settings.shared.repeatMode.rawValue), autoPlayNext=\(Settings.shared.autoPlayNext)")

        let repeatMode = Settings.shared.repeatMode
        let autoPlayNext = Settings.shared.autoPlayNext

        switch repeatMode {
        case .one:
            // Repeat current video
            avQueuePlayer?.seek(to: .zero)
            avQueuePlayer?.play()
            log("Repeating current video")

        case .all:
            // AVQueuePlayer auto-advances via actionAtItemEnd = .advance
            // Only if autoPlayNext is enabled
            if autoPlayNext {
                if let playlist = playlist, currentIndex + 1 >= playlist.count {
                    // At the end, loop back to beginning
                    currentIndex = 0
                    rebuildQueueAndPlay()
                } else {
                    currentIndex += 1
                    updateNavigationButtons()
                    resetControlsHideTimer()
                    log("▶️ AVQueuePlayer auto-advancing (all): index \(currentIndex)")
                }
            } else {
                log("⏹️ Auto-play disabled, stopping at index \(currentIndex)")
            }

        case .off:
            // Auto play next if enabled and there are more videos
            if autoPlayNext, let playlist = playlist, currentIndex + 1 < playlist.count {
                // Let AVQueuePlayer auto-advance (actionAtItemEnd = .advance)
                // Just update currentIndex for tracking
                currentIndex += 1

                updateNavigationButtons()
                resetControlsHideTimer()
                log("▶️ AVQueuePlayer will auto-advance to index \(currentIndex)")
            } else {
                log("⏹️ Auto-play disabled or end of playlist, stopping")
            }
        }
    }

    private func rebuildQueueAndPlay() {
        guard let playlist = playlist else { return }

        // Remove old observer
        if let observer = timeObserver {
            avQueuePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Remove old player layer
        avPlayerLayer?.removeFromSuperlayer()
        avPlayerLayer = nil

        // Stop current player
        avQueuePlayer?.pause()
        avQueuePlayer = nil

        // Build queue from beginning
        var items: [AVPlayerItem] = []
        for i in currentIndex..<playlist.count {
            items.append(AVPlayerItem(url: playlist[i]))
        }

        let player = AVQueuePlayer(items: items)
        let shouldAutoPlay = Settings.shared.autoPlayNext
        player.actionAtItemEnd = shouldAutoPlay ? .advance : .pause
        avQueuePlayer = player

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = videoView.bounds
        playerLayer.videoGravity = Settings.shared.defaultAspectRatio.videoGravity
        videoView.layer.addSublayer(playerLayer)
        avPlayerLayer = playerLayer

        // Setup time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateProgress()
        }

        // Observe end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        activateAudioSession()
        player.play()
        updateNavigationButtons()
        updateNowPlayingInfo()
        log("🔄 Queue rebuilt from index \(currentIndex)")
    }

    private func activateAudioSession() {
        // Activate for background play setting OR background/pip exit behavior
        let shouldActivate = Settings.shared.backgroundPlay || Settings.shared.exitBehavior == .background || Settings.shared.exitBehavior == .pip
        guard shouldActivate else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker, .allowAirPlay])
            try session.setActive(true)

            // Enable remote control events for Dynamic Island
            UIApplication.shared.beginReceivingRemoteControlEvents()

            setupRemoteControls()
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("📱 Live Activities not enabled")
            return
        }

        let attributes = LunapeekWidgetAttributes(name: "Lunapeek")

        guard let player = avQueuePlayer, let currentItem = player.currentItem else { return }

        let currentUrl = url
        let title = currentUrl.deletingPathExtension().lastPathComponent
        let duration = currentItem.duration.seconds
        let isVideo = currentUrl.pathExtension.lowercased() != "mp3" && currentUrl.pathExtension.lowercased() != "m4a"

        // Get file size
        var fileSize = "Unknown"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: currentUrl.path),
           let size = attrs[.size] as? Int64 {
            fileSize = formatFileSize(size)
        }

        let initialState = LunapeekWidgetAttributes.ContentState(
            title: title,
            duration: duration,
            currentTime: 0,
            isPlaying: true,
            fileSize: fileSize,
            isVideo: isVideo,
            thumbnailData: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            log("📱 Live Activity started: \(activity.id)")
        } catch {
            log("📱 Failed to start Live Activity: \(error)")
        }
    }

    private func updateLiveActivity() {
        guard let activity = currentActivity,
              let player = avQueuePlayer,
              let currentItem = player.currentItem else { return }

        let currentTime = player.currentTime().seconds
        let duration = currentItem.duration.seconds
        let isPlaying = player.timeControlStatus == .playing

        let state = LunapeekWidgetAttributes.ContentState(
            title: url.deletingPathExtension().lastPathComponent,
            duration: duration,
            currentTime: currentTime,
            isPlaying: isPlaying,
            fileSize: "Unknown",
            isVideo: true,
            thumbnailData: nil
        )

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    private func endLiveActivity() {
        guard let activity = currentActivity else { return }

        let finalState = LunapeekWidgetAttributes.ContentState(
            title: "Finished",
            duration: 0,
            currentTime: 0,
            isPlaying: false,
            fileSize: "",
            isVideo: false,
            thumbnailData: nil
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func setupRemoteControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Remove existing targets first
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)

        // Play command
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.avQueuePlayer?.play()
            self?.isPaused = false
            self?.setPlayButtonIcon(isPlaying: true)
            self?.updateCenterButtons()
            self?.updateNowPlayingInfo()
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.avQueuePlayer?.pause()
            self?.isPaused = true
            self?.setPlayButtonIcon(isPlaying: false)
            self?.updateCenterButtons()
            self?.updateNowPlayingInfo()
            return .success
        }

        // Update now playing info
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let player = avQueuePlayer, let currentItem = player.currentItem else { return }

        // Get current URL from player item
        let currentUrl: URL
        if let asset = currentItem.asset as? AVURLAsset {
            currentUrl = asset.url
        } else {
            currentUrl = url
        }

        let title = currentUrl.deletingPathExtension().lastPathComponent
        let duration = currentItem.duration.seconds
        let currentTime = player.currentTime().seconds
        let playbackRate = player.rate

        log("📝 NowPlaying: \(title), rate=\(playbackRate), time=\(currentTime)/\(duration)")

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        nowPlayingInfoCenter.nowPlayingInfo = info
        log("📝 NowPlaying info updated, mediaType=audio for Dynamic Island")
    }

    private func deactivateAudioSession() {
        // Only deactivate if background play is disabled AND exit behavior is pause
        let shouldDeactivate = !Settings.shared.backgroundPlay && Settings.shared.exitBehavior == .pause
        guard shouldDeactivate else { return }

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
    }

    @objc private func toggleControls() {
        // Dismiss any slider popups first
        if brightnessSliderView != nil || volumeSliderView != nil || speedPopupView != nil {
            dismissSliderPopups()
            speedPopupView?.removeFromSuperview()
            speedPopupView = nil
            return
        }

        if isControlsHidden {
            showControls()
        } else {
            // If locked, don't hide controls - only unlock button should work
            if isLocked {
                return
            }
            hideControls()
        }
    }

    // MARK: - Pan Gesture for Brightness/Volume/Seek

    private var initialPanY: CGFloat = 0
    private var initialPanX: CGFloat = 0
    private var isAdjustingBrightness = false
    private var isSeeking = false
    private var seekAccumulated: TimeInterval = 0
    private var seekStartSeconds: TimeInterval = 0

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        // Ignore pan gestures when locked
        if isLocked {
            return
        }

        let location = gesture.location(in: view)

        switch gesture.state {
        case .began:
            initialPanY = location.y
            initialPanX = location.x
            let velocity = gesture.velocity(in: view)
            // Determine direction based on initial velocity
            isSeeking = abs(velocity.x) > abs(velocity.y)
            isAdjustingBrightness = !isSeeking && location.x < view.bounds.width / 2
            if isSeeking {
                // Get current playback position
                if let player = avQueuePlayer {
                    seekStartSeconds = player.currentTime().seconds
                } else {
                    seekStartSeconds = 0
                }
                seekAccumulated = 0
            }

        case .changed:
            if isSeeking {
                // Horizontal swipe for seeking
                let deltaX = location.x - initialPanX
                // 1 pixel = 0.5 second, scale with width for consistency
                let seekDelta = TimeInterval(deltaX * 0.5)
                let newTime = seekStartSeconds + seekDelta

                // Clamp to valid range
                let duration = avQueuePlayer?.currentItem?.duration.seconds ?? 0
                let clampedTime = max(0, min(duration, newTime))

                showSeekIndicator(seconds: clampedTime)

                // Seek to position (throttled)
                let time = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
                avQueuePlayer?.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
            } else {
                // Vertical swipe for brightness/volume
                let deltaY = initialPanY - location.y
                let sensitivity: CGFloat = 300
                let change = deltaY / sensitivity

                if isAdjustingBrightness {
                    let newBrightness = max(0, min(1, UIScreen.main.brightness + change * 0.1))
                    UIScreen.main.brightness = newBrightness
                    showGestureIndicator(type: .brightness, value: newBrightness)
                } else {
                    if let slider = volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider {
                        let newVolume = max(0, min(1, slider.value + Float(change * 0.1)))
                        slider.value = newVolume
                        showGestureIndicator(type: .volume, value: CGFloat(newVolume))
                    }
                }
                initialPanY = location.y
            }

        case .ended, .cancelled:
            if isSeeking {
                // Hide seek indicator after 1 second
                seekIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    self?.seekIndicatorView?.removeFromSuperview()
                    self?.seekIndicatorView = nil
                }
            }
            isSeeking = false

        default:
            break
        }
    }

    // MARK: - Seek Indicator

    private var seekIndicatorView: UIView?
    private var seekIndicatorTimer: Timer?

    private func showSeekIndicator(seconds: TimeInterval) {
        seekIndicatorTimer?.invalidate()
        seekIndicatorView?.removeFromSuperview()

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let label = UILabel()
        label.textColor = .white
        label.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)

        let duration = avQueuePlayer?.currentItem?.duration.seconds ?? 0
        let currentStr = formatTime(seconds)
        let durationStr = formatTime(duration)
        label.text = "\(currentStr) / \(durationStr)"
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 140),
            container.heightAnchor.constraint(equalToConstant: 44),

            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        seekIndicatorView = container

        // Auto-hide after 1 second
        seekIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.seekIndicatorView?.removeFromSuperview()
            self?.seekIndicatorView = nil
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
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
        // Ignore double tap when locked
        if isLocked {
            return
        }
        // TODO: Toggle between fit and fill
    }

    @objc private func closeTapped() {
        // Close button just dismisses the player, doesn't start PiP
        // PiP is only for when app goes to background (Home button)
        cleanupAndDismiss()
    }

    private func cleanupAndDismiss() {
        // End Live Activity
        endLiveActivity()

        if let observer = timeObserver {
            avQueuePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        avQueuePlayer?.pause()
        avQueuePlayer = nil
        avPlayerLayer?.removeFromSuperlayer()
        avPlayerLayer = nil
        pipController = nil
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
        if let player = avQueuePlayer {
            if player.timeControlStatus == .playing {
                player.pause()
                isPaused = true
                setPlayButtonIcon(isPlaying: false)
            } else {
                player.play()
                if currentRate != 1.0 {
                    player.rate = currentRate
                }
                isPaused = false
                setPlayButtonIcon(isPlaying: true)
            }
            updateCenterButtons()
            return
        }

        // Handle PlayerEngine
        guard let engine = playerEngine else { return }

        switch engine.state {
        case .ready, .paused:
            engine.play()
            isPaused = false
            setPlayButtonIcon(isPlaying: true)
        case .playing:
            engine.pause()
            isPaused = true
            setPlayButtonIcon(isPlaying: false)
        default:
            break
        }
        updateCenterButtons()
    }

    private func setPlayButtonIcon(isPlaying: Bool) {
        let imageName = isPlaying ? "pause.fill" : "play.fill"
        let image = UIImage(systemName: imageName)?
            .applyingSymbolConfiguration(.init(pointSize: 36, weight: .bold, scale: .large))
        playButton.setImage(image, for: .normal)
    }

    @objc private func progressChanged() {
        guard let player = avQueuePlayer else { return }

        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration > 0 else { return }

        let targetTime = duration * Double(progressBar.value) / 100
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player.seek(to: cmTime)

        // Show time indicator
        showSeekIndicator(seconds: targetTime)

        // Reset controls hide timer
        resetControlsHideTimer()
    }

    private func updateProgress() {
        guard let player = avQueuePlayer else { return }

        let currentTime = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0

        if duration > 0 {
            let progress = (currentTime / duration) * 100
            progressBar.value = Float(progress)

            let currentStr = formatTime(currentTime)
            let durationStr = formatTime(duration)
            timeLabel.text = "\(currentStr) / \(durationStr)"

            // Update now playing info for Dynamic Island
            updateNowPlayingInfo()

            // Update Live Activity
            updateLiveActivity()
        }
    }

    private func updatePlayButton() {
        let isPlaying: Bool
        if let player = avQueuePlayer {
            isPlaying = player.timeControlStatus == .playing
        } else if playerEngine?.state == .playing {
            isPlaying = true
        } else {
            isPlaying = false
        }
        setPlayButtonIcon(isPlaying: isPlaying)
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

// MARK: - Picture in Picture Delegate

extension PlayerViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        // Hide controls when PiP starts
        hideControls()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        // Show controls when PiP stops
        showControls()
        // Update button state based on current playback status
        if let player = avQueuePlayer {
            isPaused = (player.timeControlStatus != .playing)
            setPlayButtonIcon(isPlaying: !isPaused)
            updateCenterButtons()
        }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        log("PiP failed to start: \(error.localizedDescription)")
    }
}

extension UITextView {
    func scrollToBottom() {
        let range = NSMakeRange(text.count - 1, 1)
        scrollRangeToVisible(range)
    }
}
