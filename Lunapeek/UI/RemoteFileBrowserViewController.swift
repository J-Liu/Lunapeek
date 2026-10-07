// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class RemoteFileBrowserViewController: UIViewController {
    private let server: SavedServer
    private var currentPath: String = "/"
    private var items: [RemoteFileItem] = []
    private var selectedItems: Set<IndexPath> = []
    private var isSelecting = false

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let itemWidth = (UIScreen.main.bounds.width - 44) / 2
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth * 0.6)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.delegate = self
        cv.dataSource = self
        cv.register(FileItemCell.self, forCellWithReuseIdentifier: "FileItemCell")
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    init(server: SavedServer) {
        self.server = server
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadDirectory()
    }

    private func setupUI() {
        title = server.name
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Select",
            style: .plain,
            target: self,
            action: #selector(toggleSelect)
        )

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(title: "Download", style: .plain, target: self, action: #selector(downloadSelected)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Delete", style: .plain, target: self, action: #selector(deleteSelected))
        ]
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        updateToolbar()
    }

    private func loadDirectory() {
        // TODO: Load from actual server
        items = [
            RemoteFileItem(name: "Documents", isDirectory: true, size: nil, modified: nil),
            RemoteFileItem(name: "Downloads", isDirectory: true, size: nil, modified: nil),
            RemoteFileItem(name: "video.mp4", isDirectory: false, size: 1024 * 1024 * 500, modified: Date()),
            RemoteFileItem(name: "audio.mp3", isDirectory: false, size: 1024 * 1024 * 5, modified: Date())
        ]
        collectionView.reloadData()
    }

    private func updateToolbar() {
        navigationItem.rightBarButtonItem?.title = isSelecting ? "Cancel" : "Select"
        navigationController?.toolbar.isHidden = !isSelecting || selectedItems.isEmpty
    }

    @objc private func toggleSelect() {
        isSelecting.toggle()
        selectedItems.removeAll()
        collectionView.reloadData()
        updateToolbar()
    }

    @objc private func downloadSelected() {
        guard !selectedItems.isEmpty else { return }
        let files = selectedItems.map { items[$0.item] }
        print("Download: \(files.map { $0.name })")
        // TODO: Implement download
    }

    @objc private func deleteSelected() {
        guard !selectedItems.isEmpty else { return }
        let files = selectedItems.map { items[$0.item] }

        let alert = UIAlertController(
            title: "Delete \(files.count) item(s)?",
            message: files.map { $0.name }.joined(separator: "\n"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            // TODO: Implement delete
            self?.selectedItems.removeAll()
            self?.collectionView.reloadData()
            self?.updateToolbar()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

extension RemoteFileBrowserViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FileItemCell", for: indexPath) as! FileItemCell
        let item = items[indexPath.item]
        let isSelected = selectedItems.contains(indexPath)
        cell.configure(with: item, isSelected: isSelected)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        if isSelecting {
            if selectedItems.contains(indexPath) {
                selectedItems.remove(indexPath)
            } else {
                selectedItems.insert(indexPath)
            }
            collectionView.reloadItems(at: [indexPath])
            updateToolbar()
        } else {
            let item = items[indexPath.item]
            if item.isDirectory {
                // Navigate into directory
                currentPath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
                loadDirectory()
            } else {
                // Open file
                print("Open: \(item.name)")
            }
        }
    }
}

struct RemoteFileItem {
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
}

final class FileItemCell: UICollectionViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkmark = UIImageView()

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

        iconView.tintColor = .systemBlue
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailLabel)

        checkmark.image = UIImage(systemName: "checkmark.circle.fill")
        checkmark.tintColor = .systemBlue
        checkmark.isHidden = true
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            iconView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.55),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            checkmark.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with item: RemoteFileItem, isSelected: Bool) {
        titleLabel.text = item.name

        if item.isDirectory {
            iconView.image = UIImage(systemName: "folder.fill")
            iconView.tintColor = .systemBlue
            detailLabel.text = nil
        } else {
            let ext = (item.name as NSString).pathExtension.lowercased()
            switch ext {
            case "mp4", "mov", "avi", "mkv", "webm":
                iconView.image = UIImage(systemName: "video.fill")
                iconView.tintColor = .systemPurple
            case "mp3", "wav", "flac", "aac", "m4a":
                iconView.image = UIImage(systemName: "music.note")
                iconView.tintColor = .systemPink
            case "jpg", "jpeg", "png", "gif", "heic":
                iconView.image = UIImage(systemName: "photo.fill")
                iconView.tintColor = .systemGreen
            default:
                iconView.image = UIImage(systemName: "doc.fill")
                iconView.tintColor = .systemGray
            }

            if let size = item.size {
                detailLabel.text = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            } else {
                detailLabel.text = nil
            }
        }

        checkmark.isHidden = !isSelected
    }
}
