// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import PhotosUI
import UIKit

enum MediaType {
    case video, audio
}

final class MediaLibraryViewController: UIViewController {
    private let mediaType: MediaType
    private var items: [LocalMediaItem] = []
    private var collectionView: UICollectionView!

    init(mediaType: MediaType) {
        self.mediaType = mediaType
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadMedia()
    }

    private func setupUI() {
        title = mediaType == .video ? "Video" : "Audio"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addMediaTapped)
        )

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let itemWidth = (UIScreen.main.bounds.width - 44) / 2
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth * 0.75)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(MediaItemCell.self, forCellWithReuseIdentifier: "MediaItemCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadMedia() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var newItems: [LocalMediaItem] = []

        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v", "flv"]
        let audioExtensions = ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma"]

        let extensions = mediaType == .video ? videoExtensions : audioExtensions

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            for file in files {
                let ext = file.pathExtension.lowercased()
                if extensions.contains(ext) {
                    let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let item = LocalMediaItem(
                        name: file.lastPathComponent,
                        url: file,
                        size: Int64(attrs.fileSize ?? 0),
                        modified: attrs.contentModificationDate
                    )
                    newItems.append(item)
                }
            }

            newItems.sort { $0.modified ?? .distantPast > $1.modified ?? .distantPast }
        } catch {
            print("Error loading media: \(error)")
        }

        items = newItems
        collectionView.reloadData()
    }

    @objc private func addMediaTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Import from Files", style: .default) { [weak self] _ in
            self?.showFilePicker()
        })

        alert.addAction(UIAlertAction(title: "Import from Photos", style: .default) { [weak self] _ in
            self?.showPhotoPicker()
        })

        alert.addAction(UIAlertAction(title: "Open URL", style: .default) { [weak self] _ in
            self?.showURLInput()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func showFilePicker() {
        let types: [UTType] = mediaType == .video ? [.movie, .video, .mpeg4Movie] : [.audio, .mp3, .aiff, .wav, .mpeg4Audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    private func showPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = mediaType == .video ? .videos : .any(of: [.videos, .livePhotos])

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showURLInput() {
        let alert = UIAlertController(title: "Open URL", message: "Enter a video or audio URL", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/video.mp4"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.keyboardType = .URL
        }

        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let url = URL(string: text) else { return }
            self?.play(url: url)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func play(url: URL) {
        let playerVC = PlayerViewController(url: url)
        playerVC.modalPresentationStyle = .fullScreen
        present(playerVC, animated: true)
    }

    private func delete(item: LocalMediaItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            loadMedia()
        } catch {
            let alert = UIAlertController(
                title: "Delete Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

extension MediaLibraryViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MediaItemCell", for: indexPath) as! MediaItemCell
        let item = items[indexPath.item]
        cell.configure(with: item, mediaType: mediaType)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = items[indexPath.item]
        play(url: item.url)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = items[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.delete(item: item)
            }

            let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                let activityVC = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
                self?.present(activityVC, animated: true)
            }

            return UIMenu(title: "", children: [shareAction, deleteAction])
        }
    }
}

extension MediaLibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for url in urls {
            let destURL = documentsPath.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                print("Error copying file: \(error)")
            }
        }
        loadMedia()
    }
}

extension MediaLibraryViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        let itemProvider = result.itemProvider
        let typeIdentifier = mediaType == .video ? UTType.movie.identifier : UTType.audio.identifier

        if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
                guard let url = url else { return }
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destURL = documentsPath.appendingPathComponent(url.lastPathComponent)

                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)

                    DispatchQueue.main.async {
                        self?.loadMedia()
                    }
                } catch {
                    print("Error copying file: \(error)")
                }
            }
        }
    }
}

struct LocalMediaItem {
    let name: String
    let url: URL
    let size: Int64
    let modified: Date?
}

final class MediaItemCell: UICollectionViewCell {
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        thumbnailView.backgroundColor = .tertiarySystemBackground
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.6),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    func configure(with item: LocalMediaItem, mediaType: MediaType) {
        titleLabel.text = item.name
        thumbnailView.image = UIImage(systemName: mediaType == .video ? "video.fill" : "music.note")
        thumbnailView.tintColor = .systemGray3
        thumbnailView.contentMode = .center

        if let modified = item.modified {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            detailLabel.text = formatter.string(from: modified)
        } else {
            detailLabel.text = nil
        }
    }
}
