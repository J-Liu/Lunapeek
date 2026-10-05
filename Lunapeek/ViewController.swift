// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu. All rights reserved.

import UIKit

class ViewController: UIViewController {
    private var playerEngine: PlayerEngine?
    private var videoView: UIView!
    private var playButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPlayer()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        videoView = UIView(frame: .zero)
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)

        playButton = UIButton(type: .system)
        playButton.setTitle("Open File", for: .normal)
        playButton.addTarget(self, action: #selector(openFileTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playButton)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.topAnchor.constraint(equalTo: videoView.bottomAnchor, constant: 20)
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerEngine?.videoRendererLayer?.frame = videoView.bounds
    }

    @objc private func openFileTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video, .audio])
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func playPauseTapped() {
        guard let engine = playerEngine else { return }

        switch engine.state {
        case .ready, .paused:
            engine.play()
            playButton.setTitle("Pause", for: .normal)
        case .playing:
            engine.pause()
            playButton.setTitle("Play", for: .normal)
        default:
            break
        }
    }
}

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        Task {
            do {
                try await playerEngine?.load(url: url)
                playerEngine?.play()
                playButton.removeTarget(self, action: #selector(openFileTapped), for: .touchUpInside)
                playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
                playButton.setTitle("Pause", for: .normal)
            } catch {
                print("Failed to load: \(error)")
            }
        }
    }
}

