// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class PlayerViewController: UIViewController {
    private let url: URL
    private var playerEngine: PlayerEngine?
    private var videoView: UIView!

    private var controlView: UIView!
    private var playButton: UIButton!
    private var closeButton: UIButton!
    private var progressBar: UISlider!
    private var timeLabel: UILabel!
    private var isControlsHidden = false

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPlayer()
        setupGestures()
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

            controlView.topAnchor.constraint(equalTo: view.topAnchor),
            controlView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

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

    private func setupPlayer() {
        let demuxer = SystemDemuxerPlugin()
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
                try await playerEngine?.load(url: url)
                playerEngine?.play()
                updatePlayButton()
            } catch {
                print("Failed to load: \(error)")
                showError(error)
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
        Task {
            await playerEngine?.stop()
            await MainActor.run {
                self.dismiss(animated: true)
            }
        }
    }

    @objc private func playPauseTapped() {
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
        // TODO: Seek to position
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
        let alert = UIAlertController(
            title: "Playback Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerEngine?.videoRendererLayer?.frame = videoView.bounds
    }
}
