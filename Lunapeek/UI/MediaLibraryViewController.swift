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
    private var items: [MediaItem] = []
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
        // TODO: Load from Documents directory and media library
        items = [
            MediaItem(name: "Sample Video", type: mediaType, thumbnail: nil),
            MediaItem(name: "Another File", type: mediaType, thumbnail: nil)
        ]
        collectionView.reloadData()
    }

    @objc private func addMediaTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
            self?.showFilePicker()
        })

        alert.addAction(UIAlertAction(title: "Photos", style: .default) { [weak self] _ in
            self?.showPhotoPicker()
        })

        alert.addAction(UIAlertAction(title: "URL", style: .default) { [weak self] _ in
            self?.showURLInput()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func showFilePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: mediaType == .video ? [.movie, .video] : [.audio])
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
}

extension MediaLibraryViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MediaItemCell", for: indexPath) as! MediaItemCell
        cell.configure(with: items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        // TODO: Open media item
    }
}

extension MediaLibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        play(url: url)
    }
}

extension MediaLibraryViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        let itemProvider = result.itemProvider
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        self?.play(url: url)
                    }
                }
            }
        }
    }
}

struct MediaItem {
    let name: String
    let type: MediaType
    let thumbnail: UIImage?
}

final class MediaItemCell: UICollectionViewCell {
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()

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

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.7),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    func configure(with item: MediaItem) {
        titleLabel.text = item.name
        thumbnailView.image = item.thumbnail ?? UIImage(systemName: item.type == .video ? "video.fill" : "music.note")
        thumbnailView.tintColor = .systemGray3
        thumbnailView.contentMode = item.thumbnail == nil ? .center : .scaleAspectFill
    }
}
