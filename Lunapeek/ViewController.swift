// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import UniformTypeIdentifiers

class ViewController: UIViewController {
    private var lpPlayerEngine: LPPlayerEngine?
    private var lpVideoRenderer: LPVideoRenderer?
    private var lpAudioRenderer: LPAudioRenderer?
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
        let videoRenderer = LPVideoRenderer()
        let audioRenderer = LPAudioRenderer()
        lpVideoRenderer = videoRenderer
        lpAudioRenderer = audioRenderer

        lpPlayerEngine = LPPlayerEngine()
        lpPlayerEngine?.videoRenderer = { [weak self] frame in
            videoRenderer.enqueue(frame)
        }
        lpPlayerEngine?.audioRenderer = { [weak self] frame in
            audioRenderer.enqueue(frame)
        }

        videoView.layer.addSublayer(videoRenderer.layer)
        videoRenderer.layer.frame = videoView.bounds
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        lpVideoRenderer?.layer.frame = videoView.bounds
    }

    @objc private func openFileTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video, .audio])
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func playPauseTapped() {
        guard let engine = lpPlayerEngine else { return }

        switch engine.state {
        case .ready, .paused:
            engine.play()
            lpAudioRenderer?.play()
            playButton.setTitle("Pause", for: .normal)
        case .playing:
            engine.pause()
            lpAudioRenderer?.pause()
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
                try await lpPlayerEngine?.open(url: url)
                lpAudioRenderer?.play()
                lpPlayerEngine?.play()
                playButton.removeTarget(self, action: #selector(openFileTapped), for: .touchUpInside)
                playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
                playButton.setTitle("Pause", for: .normal)
            } catch {
                print("Failed to load: \(error)")
            }
        }
    }
}
