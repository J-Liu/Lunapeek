// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class RemoteFileBrowserViewController: UIViewController, UIGestureRecognizerDelegate {
    private let server: SavedServer
    private var currentPath: String
    private var items: [RemoteFileItem] = []
    private var selectedItems: Set<IndexPath> = []
    private var isSelecting = false

    private var smbClient: SMBClientWrapper?
    private var sftpClient: SFTPClientWrapper?
    private weak var currentMenuVC: UIViewController?

    // Track downloading files: path -> progress (0-1)
    private var downloadingFiles: [String: Float] = [:]
    // Track completed downloads for showing prompt
    private var completedDownloads: [String] = []

    // Download completion banner
    private var downloadBanner: UIView?
    private var downloadBannerHeightConstraint: NSLayoutConstraint?

    // Keep-alive timer for SMB/SFTP connections
    private var keepAliveTimer: Timer?

    // Swipe selection
    private var isSwipeSelecting = false
    private var swipeSelectingState: Bool = true
    private var swipeSelectingStartIndex: Int?
    private var autoScrollTimer: Timer?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?

    // Debug log
    private var debugTextView: UITextView!

    private func appendDebugLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(text)\n"
        DispatchQueue.main.async { [weak self] in
            self?.debugTextView.text = (self?.debugTextView.text ?? "") + line
            let bottom = NSRange(location: self?.debugTextView.text.count ?? 0, length: 0)
            self?.debugTextView.scrollRangeToVisible(bottom)
        }
    }

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
        cv.isScrollEnabled = true
        cv.alwaysBounceVertical = true
        cv.showsVerticalScrollIndicator = true
        cv.register(FileItemCell.self, forCellWithReuseIdentifier: "FileItemCell")
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionViewLayout()

        // Debug: log scroll state
        appendDebugLog("bounds: \(Int(collectionView.bounds.width))x\(Int(collectionView.bounds.height)), content: \(Int(collectionView.contentSize.width))x\(Int(collectionView.contentSize.height))")
    }

    private func updateCollectionViewLayout() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }

        // Ensure collection view has valid bounds before calculating
        guard collectionView.bounds.width > 0 else { return }

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
        stopKeepAliveTimer()
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

        // Navigation bar buttons - Select + Download + Delete
        let selectButton = UIBarButtonItem(
            title: NSLocalizedString("Select", comment: ""),
            style: .plain,
            target: self,
            action: #selector(toggleSelect)
        )

        let downloadButton = UIBarButtonItem(
            title: NSLocalizedString("Download", comment: ""),
            style: .plain,
            target: self,
            action: #selector(downloadSelected)
        )

        let deleteButton = UIBarButtonItem(
            title: NSLocalizedString("Delete", comment: ""),
            style: .plain,
            target: self,
            action: #selector(deleteSelected)
        )

        navigationItem.rightBarButtonItems = [selectButton, downloadButton, deleteButton]

        view.addSubview(collectionView)

        // Setup swipe selection gestures
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGestureRecognizer?.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPressGestureRecognizer!)

        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGestureRecognizer?.delegate = self
        collectionView.addGestureRecognizer(panGestureRecognizer!)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // Debug text view
        debugTextView = UITextView()
        debugTextView.isEditable = false
        debugTextView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        debugTextView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        debugTextView.textColor = .green
        debugTextView.isHidden = true
        debugTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugTextView)

        NSLayoutConstraint.activate([
            debugTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            debugTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            debugTextView.heightAnchor.constraint(equalToConstant: 100)
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
                startKeepAliveTimer()
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

    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.checkConnection()
            }
        }
    }

    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func checkConnection() async {
        // Try to verify connection by listing current directory
        var needsReconnect = false

        if smbClient != nil {
            do {
                _ = try await smbClient!.listDirectory(path: currentPath)
            } catch {
                needsReconnect = true
            }
        } else if sftpClient != nil {
            do {
                _ = try await sftpClient!.listDirectory(path: currentPath)
            } catch {
                needsReconnect = true
            }
        }

        if needsReconnect {
            // Connection is broken, try to reconnect
            if smbClient != nil {
                await reconnectSMB()
            } else if sftpClient != nil {
                await reconnectSFTP()
            }
        }
    }

    private func reconnectSMB() async {
        guard let shareName = server.share, !shareName.isEmpty else { return }

        do {
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
            await loadDirectory()
        } catch {
            // Reconnection failed, will retry on next keep-alive check
        }
    }

    private func reconnectSFTP() async {
        do {
            let client = SFTPClientWrapper()
            let config = SFTPConfiguration(
                host: server.address,
                port: server.port ?? 22,
                username: server.username,
                password: server.password
            )
            try await client.connect(configuration: config)
            sftpClient = client
            do {
                currentPath = try await client.getHomeDirectory()
            } catch {
                currentPath = "/"
            }
            await loadDirectory()
        } catch {
            // Reconnection failed, will retry on next keep-alive check
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
                self.appendDebugLog("Loaded \(filteredFiles.count) items, contentSize: \(Int(self.collectionView.contentSize.height))")
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
        // Only show Select button when not selecting
        if !isSelecting {
            let selectButton = UIBarButtonItem(
                title: NSLocalizedString("Select", comment: ""),
                style: .plain,
                target: self,
                action: #selector(toggleSelect)
            )
            navigationItem.rightBarButtonItems = [selectButton]
        } else {
            // Show Delete, Download, Cancel when selecting
            let deleteButton = UIBarButtonItem(
                title: NSLocalizedString("Delete", comment: ""),
                style: .plain,
                target: self,
                action: #selector(deleteSelected)
            )
            deleteButton.tintColor = .systemRed

            let hasSelection = !selectedItems.isEmpty
            deleteButton.isEnabled = hasSelection

            let downloadButton = UIBarButtonItem(
                title: NSLocalizedString("Download", comment: ""),
                style: .plain,
                target: self,
                action: #selector(downloadSelected)
            )
            downloadButton.isEnabled = hasSelection

            let cancelButton = UIBarButtonItem(
                title: NSLocalizedString("Cancel", comment: ""),
                style: .plain,
                target: self,
                action: #selector(toggleSelect)
            )

            // Delete on left, Download + Cancel on right
            navigationItem.rightBarButtonItems = [deleteButton, downloadButton, cancelButton]
        }
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

        // Keep screen on during download
        UIApplication.shared.isIdleTimerDisabled = true
        print("[Download] Screen will stay on, idleTimerDisabled = true")

        Task { [weak self] in
            guard let self else { return }

            // Check and reconnect if needed before download
            await self.checkConnection()

            // Track download progress
            for file in files {
                guard !file.isDirectory else { continue }
                let remotePath = self.currentPath == "/" ? "/\(file.name)" : "\(self.currentPath)/\(file.name)"
                await MainActor.run {
                    self.downloadingFiles[remotePath] = 0
                    self.collectionView.reloadData()
                }
            }

            for file in files {
                guard !file.isDirectory else { continue }

                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let localURL = documentsPath.appendingPathComponent(file.name)
                let remotePath = self.currentPath == "/" ? "/\(file.name)" : "\(self.currentPath)/\(file.name)"

                do {
                    if let client = self.smbClient {
                        try await client.downloadFile(remotePath: remotePath, localURL: localURL) { progress in
                            Task { @MainActor in
                                self.downloadingFiles[remotePath] = Float(progress.fraction)
                                self.collectionView.reloadData()
                            }
                        }
                    } else if let client = self.sftpClient {
                        try await client.downloadFile(remotePath: remotePath, localURL: localURL) { progress in
                            Task { @MainActor in
                                self.downloadingFiles[remotePath] = Float(progress.fraction)
                                self.collectionView.reloadData()
                            }
                        }
                    }

                    await MainActor.run {
                        self.downloadingFiles.removeValue(forKey: remotePath)
                        self.completedDownloads.append(file.name)
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        guard let self, self.isViewLoaded, self.view.window != nil else { return }
                        self.downloadingFiles.removeValue(forKey: remotePath)
                        self.collectionView.reloadData()

                        let alert = UIAlertController(
                            title: "Download Failed",
                            message: "Failed to download \(file.name): \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                    return
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.selectedItems.removeAll()
                self.collectionView.reloadData()
                self.updateToolbar()

                // Show completion prompt with "View Now" button
                self.showDownloadCompletePrompt()

                // Allow screen to sleep again
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private func showDownloadCompletePrompt() {
        let files = completedDownloads
        completedDownloads.removeAll()

        guard !files.isEmpty else { return }

        // Remove existing banner if any
        downloadBanner?.removeFromSuperview()

        // Create yellow banner
        let banner = UIView()
        banner.backgroundColor = .systemYellow
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        // "Download complete" label
        let label = UILabel()
        label.text = "Downloaded \(files.count) file(s)"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        // "View Now" button (blue, link-like)
        let viewButton = UIButton(type: .system)
        viewButton.setTitle("View Now", for: .normal)
        viewButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        viewButton.setTitleColor(.systemBlue, for: .normal)
        viewButton.addTarget(self, action: #selector(viewDownloadedFiles), for: .touchUpInside)
        viewButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(viewButton)

        // Auto-dismiss button (X)
        let dismissButton = UIButton(type: .system)
        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismissButton.tintColor = .darkGray
        dismissButton.addTarget(self, action: #selector(dismissDownloadBanner), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(dismissButton)

        // Layout
        let heightConstraint = banner.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        downloadBannerHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            heightConstraint,

            dismissButton.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            dismissButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 30),
            dismissButton.heightAnchor.constraint(equalToConstant: 30),

            label.leadingAnchor.constraint(equalTo: dismissButton.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),

            viewButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            viewButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])

        downloadBanner = banner

        // Animate in
        view.layoutIfNeeded()
        heightConstraint.constant = 44

        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }

        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.dismissDownloadBanner()
        }
    }

    @objc private func viewDownloadedFiles() {
        dismissDownloadBanner()
        navigateToDownloadedFile()
    }

    @objc private func dismissDownloadBanner() {
        guard let banner = downloadBanner else { return }

        downloadBannerHeightConstraint?.constant = 0
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            banner.removeFromSuperview()
            self.downloadBanner = nil
        }
    }

    private func navigateToDownloadedFile(files: [String] = []) {
        // Determine which tab to navigate to based on file types
        var hasVideo = false
        var hasAudio = false

        for file in files {
            let ext = (file as NSString).pathExtension.lowercased()
            if ["mp4", "mov", "avi", "mkv", "webm", "m4v", "flv"].contains(ext) {
                hasVideo = true
            } else if ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma"].contains(ext) {
                hasAudio = true
            }
        }

        // Navigate to media library tab
        if let nav = navigationController {
            if let tabBar = nav.tabBarController {
                // Video tab is index 0, Audio tab is index 1
                if hasVideo {
                    tabBar.selectedIndex = 0
                } else if hasAudio {
                    tabBar.selectedIndex = 1
                } else {
                    // Default to video if unknown type
                    tabBar.selectedIndex = 0
                }
            }
        }
    }

    @objc private func deleteSelected() {
        guard !selectedItems.isEmpty else { return }
        let files = selectedItems.map { items[$0.item] }

        let alert = UIAlertController(
            title: String(format: NSLocalizedString("Delete %d items?", comment: ""), files.count),
            message: files.map { $0.name }.joined(separator: "\n"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
            self?.performDelete(files: files)
        })

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
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

// MARK: - UIGestureRecognizerDelegate
extension RemoteFileBrowserViewController {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGestureRecognizer {
            // Only begin pan gesture if in selection mode, otherwise let scroll work
            return isSelecting
        }
        return true
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
        // Get download progress if this file is downloading
        let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
        let progress = downloadingFiles[remotePath]
        cell.configure(with: item, isSelected: isSelected, progress: progress)
        cell.delegate = self
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        if isSelecting {
            // Check if file is currently downloading
            let item = items[indexPath.item]
            let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
            if downloadingFiles[remotePath] != nil {
                // File is downloading, don't allow selection
                return
            }

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

    // MARK: - Swipe Selection

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let location = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }

        let item = items[indexPath.item]
        let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
        if downloadingFiles[remotePath] != nil {
            return
        }

        if !isSelecting {
            isSelecting = true
            selectedItems.insert(indexPath)
            collectionView.reloadData()
            updateToolbar()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelecting else { return }

        let point = gesture.location(in: collectionView)

        switch gesture.state {
        case .began:
            // Record starting index
            if let indexPath = collectionView.indexPathForItem(at: point) {
                swipeSelectingStartIndex = indexPath.item
            }
            handlePanSelection(at: point, from: swipeSelectingStartIndex)
        case .changed:
            // Auto-scroll at edges
            handleAutoScroll(at: gesture.location(in: view))
            handlePanSelection(at: point, from: swipeSelectingStartIndex)
        case .ended, .cancelled:
            swipeSelectingStartIndex = nil
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        default:
            break
        }
    }

    private func handlePanSelection(at point: CGPoint, from startIndex: Int?) {
        guard let start = startIndex,
              let currentIndexPath = collectionView.indexPathForItem(at: point) else { return }

        let current = currentIndexPath.item

        // Select all items between start and current
        let range = min(start, current)...max(start, current)
        var changed = false

        for i in range {
            let indexPath = IndexPath(item: i, section: 0)
            let item = items[i]
            let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"

            // Skip downloading files
            if downloadingFiles[remotePath] != nil { continue }

            if !selectedItems.contains(indexPath) {
                selectedItems.insert(indexPath)
                changed = true
            }
        }

        if changed {
            collectionView.reloadData()
            updateToolbar()
        }
    }

    private func handleAutoScroll(at point: CGPoint) {
        let scrollSpeed: CGFloat = 10
        let edgeThreshold: CGFloat = 50

        autoScrollTimer?.invalidate()

        if point.y < edgeThreshold {
            // Scroll up
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let offset = self.collectionView.contentOffset
                self.collectionView.setContentOffset(CGPoint(x: offset.x, y: max(0, offset.y - scrollSpeed)), animated: false)
            }
        } else if point.y > collectionView.bounds.height - edgeThreshold {
            // Scroll down
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let offset = self.collectionView.contentOffset
                let maxOffset = self.collectionView.contentSize.height - self.collectionView.bounds.height
                self.collectionView.setContentOffset(CGPoint(x: offset.x, y: min(maxOffset, offset.y + scrollSpeed)), animated: false)
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
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
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
        let alert = UIAlertController(title: NSLocalizedString("Rename", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = item.name
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Rename", comment: ""), style: .default) { [weak self] _ in
            guard let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }
            self?.performRename(item: item, newName: newName)
        })
        present(alert, animated: true)
    }

    private func performRename(item: RemoteFileItem, newName: String) {
        // TODO: Implement rename
        let alert = UIAlertController(title: NSLocalizedString("Not Implemented", comment: ""), message: NSLocalizedString("Rename feature coming soon", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func moveItem(_ item: RemoteFileItem) {
        // TODO: Implement move
        let alert = UIAlertController(title: NSLocalizedString("Not Implemented", comment: ""), message: NSLocalizedString("Move feature coming soon", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func copyItem(_ item: RemoteFileItem) {
        // TODO: Implement copy
        let alert = UIAlertController(title: NSLocalizedString("Not Implemented", comment: ""), message: NSLocalizedString("Copy feature coming soon", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func duplicateItem(_ item: RemoteFileItem) {
        // TODO: Implement duplicate
        let alert = UIAlertController(title: NSLocalizedString("Not Implemented", comment: ""), message: NSLocalizedString("Duplicate feature coming soon", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func confirmDeleteItem(_ item: RemoteFileItem, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: NSLocalizedString("Confirm Delete", comment: ""),
            message: item.name,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
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
    private let progressView = UIView()
    private var progressHeightConstraint: NSLayoutConstraint?

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

        // Progress view - covers the entire cell, height controlled by constraint
        progressView.isHidden = true
        progressView.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressView)

        progressHeightConstraint = progressView.heightAnchor.constraint(equalToConstant: 0)

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
            selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            progressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressHeightConstraint!
        ])
    }

    @objc private func menuTapped() {
        delegate?.fileItemCellDidTapMenu(self)
    }

    func configure(with item: RemoteFileItem, isSelected: Bool, progress: Float? = nil) {
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

        // Progress indicator - "roller blind" effect
        if let progress = progress {
            progressView.isHidden = false
            let cellHeight = max(contentView.bounds.height, 100)
            let revealedHeight = cellHeight * CGFloat(progress)
            progressHeightConstraint?.constant = cellHeight - revealedHeight

            menuButton.isEnabled = false
            menuButton.alpha = 0.5
        } else {
            progressView.isHidden = true
            progressHeightConstraint?.constant = 0

            menuButton.isEnabled = true
            menuButton.alpha = 1.0
        }
        // Force layout update
        contentView.layoutIfNeeded()
    }

}
