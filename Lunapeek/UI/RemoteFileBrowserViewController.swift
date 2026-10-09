// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class RemoteFileBrowserViewController: UIViewController {
    private let server: SavedServer
    private var currentPath: String
    private var items: [RemoteFileItem] = []
    private var selectedItems: Set<IndexPath> = []
    private var isSelecting = false

    private var smbClient: SMBClientWrapper?
    private var sftpClient: SFTPClientWrapper?
    private weak var currentMenuVC: UIViewController?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.delegate = self
        cv.dataSource = self
        cv.register(FileItemCell.self, forCellWithReuseIdentifier: "FileItemCell")
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionViewLayout()
    }

    private func updateCollectionViewLayout() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }

        let availableWidth = collectionView.bounds.width - 16
        let minItemWidth: CGFloat = 90
        let maxItemWidth: CGFloat = 120
        let itemWidth = max(minItemWidth, min(maxItemWidth, availableWidth / 3))
        let columns = floor(availableWidth / itemWidth)
        let spacing = layout.minimumInteritemSpacing * (columns - 1)
        let finalWidth = floor((availableWidth - spacing) / columns)
        // Height matches content: icon(64) + title(28) + button(24) + spacing(24) + padding(16)
        let itemHeight: CGFloat = 140

        layout.itemSize = CGSize(width: finalWidth, height: itemHeight)
    }

    init(server: SavedServer) {
        self.server = server
        // Start at root - Citadel SFTP doesn't reliably support "~" path expansion
        self.currentPath = "/"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasConnected = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasConnected {
            hasConnected = true
            connectAndLoad()
        }
    }

    deinit {
        let smb = smbClient
        let sftp = sftpClient
        Task {
            await smb?.disconnect()
            await sftp?.disconnect()
        }
    }

    private func setupUI() {
        title = server.name
        view.backgroundColor = .systemBackground

        // Custom back button
        navigationItem.hidesBackButton = true
        let backItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(handleBack)
        )
        backItem.tintColor = .label
        navigationItem.leftBarButtonItem = backItem

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

    private func connectAndLoad() {
        Task { [weak self] in
            guard let self else { return }
            do {
                switch server.type {
                case .smb:
                    guard let shareName = server.share, !shareName.isEmpty else {
                        await MainActor.run { [weak self] in
                            guard let self, isViewLoaded, view.window != nil else { return }
                            let alert = UIAlertController(
                                title: "Missing Share Name",
                                message: "Please specify a share name for this SMB server",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                                self?.navigationController?.popViewController(animated: true)
                            })
                            present(alert, animated: true)
                        }
                        return
                    }
                    let client = SMBClientWrapper()
                    let config = SMBConfiguration(
                        host: server.address,
                        port: server.port ?? 445,
                        share: shareName,
                        username: server.username,
                        password: server.password
                    )
                    try await client.connect(configuration: config)
                    smbClient = client
                case .sftp:
                    let client = SFTPClientWrapper()
                    let config = SFTPConfiguration(
                        host: server.address,
                        port: server.port ?? 22,
                        username: server.username,
                        password: server.password
                    )
                    try await client.connect(configuration: config)
                    sftpClient = client
                    // Get home directory for SFTP
                    do {
                        currentPath = try await client.getHomeDirectory()
                    } catch {
                        // Fall back to root if home directory can't be determined
                        currentPath = "/"
                    }
                case .webdav:
                    // TODO: Implement WebDAV
                    break
                }
                await loadDirectory()
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, isViewLoaded, view.window != nil else { return }
                    let alert = UIAlertController(
                        title: "Connection Failed",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                        self?.navigationController?.popViewController(animated: true)
                    })
                    present(alert, animated: true)
                }
            }
        }
    }

    private func loadDirectory() async {
        do {
            let files: [RemoteFileItem]

            if let client = smbClient {
                let smbFiles = try await client.listDirectory(path: currentPath)
                files = smbFiles.map { file in
                    RemoteFileItem(
                        name: file.name,
                        isDirectory: file.isDirectory,
                        size: file.size,
                        modified: file.modificationDate
                    )
                }
            } else if let client = sftpClient {
                let sftpFiles = try await client.listDirectory(path: currentPath)
                files = sftpFiles.map { file in
                    RemoteFileItem(
                        name: file.name,
                        isDirectory: file.isDirectory,
                        size: file.size,
                        modified: file.modificationDate
                    )
                }
            } else {
                files = []
            }

            // Filter non-media files if setting is disabled
            let filteredFiles: [RemoteFileItem]
            if Settings.shared.showNonMediaFiles {
                filteredFiles = files
            } else {
                filteredFiles = files.filter { item in
                    if item.isDirectory { return true }
                    return isMediaFile(item.name)
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.items = filteredFiles
                self.collectionView.reloadData()
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let self, isViewLoaded, view.window != nil else { return }
                let alert = UIAlertController(
                    title: "Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func isMediaFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v", "flv", "ts", "mts", "m2ts", "wmv", "rm", "rmvb", "3gp"]
        let audioExtensions = ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "ape", "alac"]
        return videoExtensions.contains(ext) || audioExtensions.contains(ext)
    }

    private func updateToolbar() {
        navigationItem.rightBarButtonItem?.title = isSelecting ? "Cancel" : "Select"
        navigationController?.toolbar.isHidden = !isSelecting || selectedItems.isEmpty
    }

    @objc private func handleBack() {
        if currentPath == "/" {
            navigationController?.popViewController(animated: true)
        } else {
            // Go up one level
            var pathComponents = currentPath.split(separator: "/")
            if pathComponents.isEmpty {
                currentPath = "/"
                title = server.name
            } else {
                pathComponents.removeLast()
                if pathComponents.isEmpty {
                    currentPath = "/"
                    title = server.name
                } else {
                    currentPath = "/" + pathComponents.joined(separator: "/")
                    title = String(pathComponents.last!)
                }
            }
            Task { [weak self] in
                await self?.loadDirectory()
            }
        }
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

        Task { [weak self] in
            guard let self else { return }
            for file in files {
                guard !file.isDirectory else { continue }

                do {
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let localURL = documentsPath.appendingPathComponent(file.name)
                    let remotePath = currentPath == "/" ? "/\(file.name)" : "\(currentPath)/\(file.name)"

                    if let client = smbClient {
                        try await client.downloadFile(remotePath: remotePath, localURL: localURL) { _ in }
                    } else if let client = sftpClient {
                        try await client.downloadFile(remotePath: remotePath, localURL: localURL) { _ in }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        guard let self, isViewLoaded, view.window != nil else { return }
                        let alert = UIAlertController(
                            title: "Download Failed",
                            message: "Failed to download \(file.name): \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        present(alert, animated: true)
                    }
                    return
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                selectedItems.removeAll()
                collectionView.reloadData()
                updateToolbar()

                let alert = UIAlertController(
                    title: "Download Complete",
                    message: "Downloaded \(files.count) file(s)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
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
            self?.performDelete(files: files)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func performDelete(files: [RemoteFileItem]) {
        Task { [weak self] in
            guard let self else { return }
            var deletedCount = 0
            var failedFiles: [String] = []

            for file in files {
                let remotePath = currentPath == "/" ? "/\(file.name)" : "\(currentPath)/\(file.name)"

                do {
                    if let client = smbClient {
                        try await client.deleteFile(path: remotePath, isDirectory: file.isDirectory)
                        deletedCount += 1
                    } else if let client = sftpClient {
                        try await client.deleteFile(path: remotePath, isDirectory: file.isDirectory)
                        deletedCount += 1
                    }
                } catch {
                    failedFiles.append(file.name)
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                selectedItems.removeAll()

                if failedFiles.isEmpty {
                    // Refresh the directory listing
                    Task { [weak self] in
                        await self?.loadDirectory()
                    }
                } else {
                    let alert = UIAlertController(
                        title: "Delete Completed",
                        message: "Deleted \(deletedCount) item(s). Failed: \(failedFiles.joined(separator: ", "))",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                        Task {
                            await self?.loadDirectory()
                        }
                    })
                    present(alert, animated: true)
                }
                updateToolbar()
            }
        }
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
        cell.delegate = self
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
                title = item.name
                Task {
                    await loadDirectory()
                }
            } else {
                // Check if video file
                let ext = (item.name as NSString).pathExtension.lowercased()
                let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v", "flv", "ts", "mts", "m2ts"]
                if videoExtensions.contains(ext) {
                    playRemoteFile(item)
                }
            }
        }
    }
}

// MARK: - FileItemCellDelegate

extension RemoteFileBrowserViewController: FileItemCellDelegate {
    func fileItemCellDidTapMenu(_ cell: FileItemCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let item = items[indexPath.item]
        showItemMenu(for: item, at: indexPath)
    }

    private func showItemMenu(for item: RemoteFileItem, at indexPath: IndexPath) {
        let menuVC = UIViewController()
        menuVC.modalPresentationStyle = .formSheet

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        menuVC.view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // Header view
        let headerView = createMenuHeader(for: item)
        stackView.addArrangedSubview(headerView)

        // Group 1: Share (special button with icon above)
        let shareButton = createShareButton { [weak self] in
            self?.shareItem(item)
        }
        stackView.addArrangedSubview(shareButton)

        // Group 2: File operations
        let group2 = createMenuGroup(actions: [
            ("arrow.down.circle", "Download", { [weak self] in self?.downloadItem(item) }, false),
            ("pencil", "Rename", { [weak self] in self?.renameItem(item) }, false),
            ("folder", "Move to", { [weak self] in self?.moveItem(item) }, false),
            ("doc.on.doc", "Copy to", { [weak self] in self?.copyItem(item) }, false),
            ("plus.square.on.square", "Duplicate", { [weak self] in self?.duplicateItem(item) }, false),
            ("trash", "Delete", { [weak self] in self?.confirmDeleteItem(item, at: indexPath) }, true)
        ])
        stackView.addArrangedSubview(group2)

        // Group 3: Info
        let group3 = createMenuGroup(actions: [
            ("info.circle", "Show Info", { [weak self] in self?.showInfo(for: item) }, false)
        ])
        stackView.addArrangedSubview(group3)

        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.backgroundColor = .secondarySystemBackground
        cancelButton.layer.cornerRadius = 12
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(dismissMenu), for: .touchUpInside)
        stackView.addArrangedSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.heightAnchor.constraint(equalToConstant: 56)
        ])

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: menuVC.view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: menuVC.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: menuVC.view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: menuVC.view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -12),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        present(menuVC, animated: true)
        currentMenuVC = menuVC
    }

    @objc private func dismissMenu() {
        currentMenuVC?.dismiss(animated: true)
    }

    private func createMenuHeader(for item: RemoteFileItem) -> UIView {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12

        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        iconView.preferredSymbolConfiguration = config
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false

        if item.isDirectory {
            iconView.image = UIImage(systemName: "folder.fill")
            iconView.tintColor = .systemBlue
        } else {
            let ext = (item.name as NSString).pathExtension.lowercased()
            switch ext {
            case "mp4", "mov", "avi", "mkv", "webm", "m4v", "flv":
                iconView.image = UIImage(systemName: "video.fill")
                iconView.tintColor = .systemPurple
            case "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma":
                iconView.image = UIImage(systemName: "music.note")
                iconView.tintColor = .systemPink
            case "jpg", "jpeg", "png", "gif", "heic":
                iconView.image = UIImage(systemName: "photo.fill")
                iconView.tintColor = .systemGreen
            default:
                iconView.image = UIImage(systemName: "doc.fill")
                iconView.tintColor = .systemGray
            }
        }
        view.addSubview(iconView)

        let nameLabel = UILabel()
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        nameLabel.text = item.name
        nameLabel.numberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        let detailLabel = UILabel()
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        var details: [String] = []
        if !item.isDirectory, let size = item.size {
            details.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modified = item.modified {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            details.append(formatter.string(from: modified))
        }
        detailLabel.text = details.isEmpty ? nil : details.joined(separator: " • ")
        view.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),

            nameLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: iconView.bottomAnchor),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ])

        return view
    }

    private func createShareButton(action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Share"
        config.image = UIImage(systemName: "square.and.arrow.up")
        config.imagePadding = 8
        config.imagePlacement = .top
        config.titleTextAttributesTransformer = .init { attributes in
            var newAttributes = attributes
            newAttributes.font = .systemFont(ofSize: 15, weight: .medium)
            return newAttributes
        }
        button.configuration = config
        button.tintColor = .label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionWrapper = { [weak self] in
            self?.dismissMenu()
            action()
        }
        button.addAction(UIAction { _ in actionWrapper() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 72)
        ])

        return button
    }

    private func createMenuGroup(actions: [(String, String, () -> Void)]) -> UIView {
        return createMenuGroup(actions: actions.map { ($0, $1, $2, false) })
    }

    private func createMenuGroup(actions: [(String, String, () -> Void, Bool)]) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        for (index, action) in actions.enumerated() {
            let button = createMenuAction(title: action.1, icon: action.0, isDestructive: action.3, action: action.2)
            stack.addArrangedSubview(button)

            if index < actions.count - 1 {
                let divider = createMenuDivider()
                stack.addArrangedSubview(divider)
            }
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func createMenuAction(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 12
        config.imagePlacement = .leading
        config.titleTextAttributesTransformer = .init { attributes in
            var newAttributes = attributes
            newAttributes.font = .systemFont(ofSize: 17)
            return newAttributes
        }
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.tintColor = isDestructive ? .systemRed : .label
        button.translatesAutoresizingMaskIntoConstraints = false

        let actionWrapper = { [weak self] in
            self?.dismissMenu()
            action()
        }
        button.addAction(UIAction { _ in actionWrapper() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        return button
    }

    private func createMenuDivider() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 60, bottom: 0, trailing: 0)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        return view
    }

    // MARK: - Menu Actions

    private func shareItem(_ item: RemoteFileItem) {
        // Download file first, then share
        let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = documentsPath.appendingPathComponent(item.name)

        Task { [weak self] in
            do {
                if let client = self?.smbClient {
                    try await client.downloadFile(remotePath: remotePath, localURL: localURL) { _ in }
                } else if let client = self?.sftpClient {
                    try await client.downloadFile(remotePath: remotePath, localURL: localURL) { _ in }
                }

                await MainActor.run {
                    let activityVC = UIActivityViewController(activityItems: [localURL], applicationActivities: nil)
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = self?.view
                        popover.sourceRect = CGRect(x: (self?.view.bounds.midX ?? 0), y: (self?.view.bounds.midY ?? 0), width: 0, height: 0)
                    }
                    self?.present(activityVC, animated: true)
                }
            } catch {
                await MainActor.run {
                    let alert = UIAlertController(title: "Share Failed", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }

    private func downloadItem(_ item: RemoteFileItem) {
        guard !item.isDirectory else { return }
        selectedItems.removeAll()
        selectedItems.insert(IndexPath(item: items.firstIndex(of: item) ?? 0, section: 0))
        downloadSelected()
    }

    private func renameItem(_ item: RemoteFileItem) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = item.name
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }
            self?.performRename(item: item, newName: newName)
        })
        present(alert, animated: true)
    }

    private func performRename(item: RemoteFileItem, newName: String) {
        // TODO: Implement rename
        let alert = UIAlertController(title: "Not Implemented", message: "Rename feature coming soon", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func moveItem(_ item: RemoteFileItem) {
        // TODO: Implement move
        let alert = UIAlertController(title: "Not Implemented", message: "Move feature coming soon", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func copyItem(_ item: RemoteFileItem) {
        // TODO: Implement copy
        let alert = UIAlertController(title: "Not Implemented", message: "Copy feature coming soon", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func duplicateItem(_ item: RemoteFileItem) {
        // TODO: Implement duplicate
        let alert = UIAlertController(title: "Not Implemented", message: "Duplicate feature coming soon", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func confirmDeleteItem(_ item: RemoteFileItem, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete \(item.isDirectory ? "Folder" : "File")?",
            message: item.name,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete(files: [item])
        })
        present(alert, animated: true)
    }

    private func showInfo(for item: RemoteFileItem) {
        var info = "Name: \(item.name)\n"
        info += "Type: \(item.isDirectory ? "Folder" : "File")\n"

        if !item.isDirectory, let size = item.size {
            info += "Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))\n"
        }

        if let modified = item.modified {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .long
            info += "Modified: \(formatter.string(from: modified))"
        }

        let alert = UIAlertController(title: "Info", message: info, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Remote File Playback

    private func playRemoteFile(_ item: RemoteFileItem) {
        let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"

        debugLog("Starting playback for: \(item.name)")
        debugLog("Remote path: \(remotePath)")

        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading...", message: "Preparing \(item.name)", preferredStyle: .alert)
        present(loadingAlert, animated: true)

        Task { [weak self] in
            guard let self else {
                await MainActor.run { loadingAlert.dismiss(animated: true) }
                return
            }

            do {
                // Get file size first
                debugLog("Getting file size...")
                let fileSize: Int64
                if let client = smbClient {
                    fileSize = try await client.getFileSize(remotePath: remotePath)
                    debugLog("File size (SMB): \(fileSize) bytes")
                } else if let client = sftpClient {
                    fileSize = try await client.getFileSize(remotePath: remotePath)
                    debugLog("File size (SFTP): \(fileSize) bytes")
                } else {
                    throw NSError(domain: "RemoteFileBrowser", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
                }

                // Create HTTP proxy server
                debugLog("Creating HTTP proxy server...")
                let proxy = HTTPProxyServer()
                try await proxy.start(fileName: item.name, fileSize: fileSize) { [weak self] offset, length in
                    debugLog("Data request: offset=\(offset), length=\(length)")
                    guard let self else { throw NSError(domain: "RemoteFileBrowser", code: 0, userInfo: [NSLocalizedDescriptionKey: "Disconnected"]) }

                    if let client = self.smbClient {
                        let data = try await client.readFile(remotePath: remotePath, offset: offset, length: length)
                        debugLog("Read \(data.count) bytes from SMB")
                        return data
                    } else if let client = self.sftpClient {
                        let data = try await client.readFile(remotePath: remotePath, offset: offset, length: length)
                        debugLog("Read \(data.count) bytes from SFTP")
                        return data
                    } else {
                        throw NSError(domain: "RemoteFileBrowser", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
                    }
                }

                guard let url = proxy.localURL else {
                    proxy.stop()
                    throw NSError(domain: "RemoteFileBrowser", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get proxy URL"])
                }
                debugLog("Proxy URL: \(url.absoluteString)")

                await MainActor.run { [weak self] in
                    loadingAlert.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        // Present player with proxy URL, pass proxy server ownership
                        let playerVC = PlayerViewController(url: url, proxyServer: proxy)
                        playerVC.modalPresentationStyle = .fullScreen
                        self.present(playerVC, animated: true)
                    }
                }
            } catch {
                debugLog("Error: \(error)")
                await MainActor.run { [weak self] in
                    loadingAlert.dismiss(animated: true)
                    let alert = UIAlertController(
                        title: "Playback Error",
                        message: "Failed to load video: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }
}

struct RemoteFileItem: Equatable {
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
}

// MARK: - FileItemCell

protocol FileItemCellDelegate: AnyObject {
    func fileItemCellDidTapMenu(_ cell: FileItemCell)
}

final class FileItemCell: UICollectionViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let menuButton = UIButton()
    private let selectionOverlay = UIView()

    weak var delegate: FileItemCellDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        // Icon - centered at top
        iconView.tintColor = .systemBlue
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // Title - centered below icon
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Menu button - centered below title
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .secondaryLabel
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(menuButton)

        // Selection overlay
        selectionOverlay.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
        selectionOverlay.layer.borderColor = UIColor.systemBlue.cgColor
        selectionOverlay.layer.borderWidth = 2
        selectionOverlay.layer.cornerRadius = 8
        selectionOverlay.isHidden = true
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionOverlay)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            menuButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            menuButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 24),
            menuButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func menuTapped() {
        delegate?.fileItemCellDidTapMenu(self)
    }

    func configure(with item: RemoteFileItem, isSelected: Bool) {
        titleLabel.text = item.name

        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        iconView.preferredSymbolConfiguration = config

        if item.isDirectory {
            iconView.image = UIImage(systemName: "folder.fill")
            iconView.tintColor = .systemBlue
        } else {
            let ext = (item.name as NSString).pathExtension.lowercased()
            switch ext {
            case "mp4", "mov", "avi", "mkv", "webm", "m4v", "flv":
                iconView.image = UIImage(systemName: "video.fill")
                iconView.tintColor = .systemPurple
            case "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma":
                iconView.image = UIImage(systemName: "music.note")
                iconView.tintColor = .systemPink
            case "jpg", "jpeg", "png", "gif", "heic":
                iconView.image = UIImage(systemName: "photo.fill")
                iconView.tintColor = .systemGreen
            default:
                iconView.image = UIImage(systemName: "doc.fill")
                iconView.tintColor = .systemGray
            }
        }

        selectionOverlay.isHidden = !isSelected
    }
}
