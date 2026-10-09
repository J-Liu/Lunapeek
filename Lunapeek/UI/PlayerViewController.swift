// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import AVFoundation

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
                self?.logEntries.append(entry)
                if self!.logEntries.count > 50 { self!.logEntries.removeFirst() }
                self?.debugTextView?.text = self?.logEntries.joined(separator: "\n")
                self?.debugTextView?.scrollToBottom()
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

        // Close button
        closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(closeButton)

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

        // Progress bar
        progressBar = UISlider()
        progressBar.minimumValue = 0
        progressBar.maximumValue = 100
        progressBar.value = 0
        progressBar.tintColor = .systemBlue
        progressBar.addTarget(self, action: #selector(progressChanged), for: .valueChanged)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(progressBar)

        // Time label
        timeLabel = UILabel()
        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        timeLabel.text = "0:00 / 0:00"
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(timeLabel)

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

            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            progressBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -48),

            timeLabel.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8)
        ])
    }

    @objc private func toggleDebug() {
        isDebugVisible.toggle()
        debugTextView.isHidden = !isDebugVisible
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
    }

    @objc private func toggleControls() {
        isControlsHidden.toggle()
        UIView.animate(withDuration: 0.3) {
            self.controlView.alpha = self.isControlsHidden ? 0 : 1
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
