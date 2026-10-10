// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import AVFoundation
import PhotosUI
import UIKit

enum MediaType {
    case video, audio
}

enum DisplayMode {
    case grid  // thumbnail or icon based on settings
    case list
}

enum SortOption: String, CaseIterable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case sizeLargest = "Size (Largest)"
    case sizeSmallest = "Size (Smallest)"
}

final class MediaLibraryViewController: UIViewController {
    private let mediaType: MediaType
    private var items: [LocalMediaItem] = []
    private var collectionView: UICollectionView!

    private var displayMode: DisplayMode = .grid
    private var sortOption: SortOption = .dateNewest
    private var isSelecting = false
    private var selectedItems: Set<IndexPath> = []

    private var displayModeButton: UIBarButtonItem!
    private var sortButton: UIBarButtonItem!
    private var selectButton: UIBarButtonItem!
    private weak var currentMenuVC: UIViewController?
    private var movingItem: LocalMediaItem?
    private var copyingItem: LocalMediaItem?

    // Swipe selection
    private var isSwipeSelecting = false
    private var swipeSelectingState: Bool = true
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?

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
        updateDisplayModeButton()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            updateLayout(layout)
        }
    }

    private var showThumbnails: Bool {
        return Settings.shared.showThumbnails
    }

    private func setupUI() {
        title = mediaType == .video ? "Video" : "Audio"
        view.backgroundColor = .systemBackground

        // Display mode toggle button
        displayModeButton = UIBarButtonItem(
            image: UIImage(systemName: "rectangle.grid.2x2"),
            style: .plain,
            target: self,
            action: #selector(toggleDisplayMode)
        )

        // Sort button
        sortButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(showSortOptions)
        )

        // Select button
        selectButton = UIBarButtonItem(
            title: "Select",
            style: .plain,
            target: self,
            action: #selector(toggleSelect)
        )

        // Add button
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addMediaTapped)
        )

        navigationItem.rightBarButtonItems = [addButton, sortButton, displayModeButton]
        navigationItem.leftBarButtonItem = selectButton

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        updateLayout(layout)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(MediaItemCell.self, forCellWithReuseIdentifier: "MediaItemCell")
        collectionView.register(IconItemCell.self, forCellWithReuseIdentifier: "IconItemCell")
        collectionView.register(ListItemCell.self, forCellWithReuseIdentifier: "ListItemCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        // Add swipe selection gestures
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGestureRecognizer?.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPressGestureRecognizer!)

        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        collectionView.addGestureRecognizer(panGestureRecognizer!)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateLayout(_ layout: UICollectionViewFlowLayout) {
        switch displayMode {
        case .grid:
            layout.minimumInteritemSpacing = showThumbnails ? 12 : 8
            layout.minimumLineSpacing = showThumbnails ? 12 : 8
            layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

            if showThumbnails {
                // Thumbnail mode: larger items
                let itemWidth = (UIScreen.main.bounds.width - 44) / 2
                layout.itemSize = CGSize(width: itemWidth, height: itemWidth * 0.75)
            } else {
                // Icon mode: 3 columns, taller cells for menu button
                let itemWidth = (UIScreen.main.bounds.width - 56) / 3
                layout.itemSize = CGSize(width: itemWidth, height: itemWidth * 1.1)
            }

        case .list:
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 0
            layout.sectionInset = .zero
            layout.itemSize = CGSize(width: UIScreen.main.bounds.width, height: 60)
        }
    }

    @objc private func toggleDisplayMode() {
        displayMode = displayMode == .grid ? .list : .grid
        updateDisplayModeButton()

        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            updateLayout(layout)
            collectionView.reloadData()
        }
    }

    @objc private func showSortOptions() {
        let alert = UIAlertController(title: "Sort By", message: nil, preferredStyle: .actionSheet)

        for option in SortOption.allCases {
            let isSelected = sortOption == option
            alert.addAction(UIAlertAction(title: option.rawValue + (isSelected ? " ✓" : ""), style: .default) { [weak self] _ in
                self?.sortOption = option
                self?.applySort()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = sortButton
        }
        present(alert, animated: true)
    }

    @objc private func toggleSelect() {
        isSelecting.toggle()
        selectedItems.removeAll()
        selectButton.title = isSelecting ? "Cancel" : "Select"
        collectionView.reloadData()

        if !isSelecting {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addMediaTapped)),
                sortButton,
                displayModeButton
            ]
        } else {
            let deleteButton = UIBarButtonItem(
                title: "Delete",
                style: .plain,
                target: self,
                action: #selector(deleteSelected)
            )
            deleteButton.tintColor = .systemRed
            navigationItem.rightBarButtonItems = [deleteButton]
        }
    }

    @objc private func deleteSelected() {
        guard !selectedItems.isEmpty else { return }
        let files = selectedItems.map { items[$0.item] }

        let alert = UIAlertController(
            title: "Delete \(files.count) item(s)?",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            for file in files {
                try? FileManager.default.removeItem(at: file.url)
            }
            self?.toggleSelect()
            self?.loadMedia()
        })
        present(alert, animated: true)
    }

    private func applySort() {
        switch sortOption {
        case .nameAsc:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .dateNewest:
            items.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case .dateOldest:
            items.sort { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .sizeLargest:
            items.sort { $0.size > $1.size }
        case .sizeSmallest:
            items.sort { $0.size < $1.size }
        }
        collectionView.reloadData()
    }

    private func updateDisplayModeButton() {
        let imageName = displayMode == .grid ? "rectangle.grid.2x2" : "list.bullet"
        displayModeButton.image = UIImage(systemName: imageName)
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
        } catch {
            print("Error loading media: \(error)")
        }

        items = newItems
        applySort()
    }

    @objc private func addMediaTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Import from Files", style: .default) { [weak self] _ in
            self?.showFilePicker()
        })

        alert.addAction(UIAlertAction(title: "Import from Photos", style: .default) { [weak self] _ in
            self?.showPhotoPicker()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func showFilePicker() {
        let types: [UTType] = mediaType == .video ? [.movie, .video, .mpeg4Movie, .item] : [.audio, .mp3, .aiff, .wav, .mpeg4Audio, .item]
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

    private func play(url: URL) {
        // Create playlist from sorted items
        let playlist = items.map { $0.url }
        let index = items.firstIndex { $0.url == url } ?? 0

        let playerVC = PlayerViewController(url: url, playlist: playlist, currentIndex: index)
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

extension MediaLibraryViewController: UICollectionViewDataSource, UICollectionViewDelegate, IconItemCellDelegate, MediaItemCellDelegate, ListItemCellDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = items[indexPath.item]
        let isSelected = selectedItems.contains(indexPath)

        switch displayMode {
        case .grid:
            if showThumbnails {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MediaItemCell", for: indexPath) as! MediaItemCell
                cell.configure(with: item, mediaType: mediaType)
                cell.configureSelection(isSelected: isSelected)
                cell.delegate = self
                return cell
            } else {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "IconItemCell", for: indexPath) as! IconItemCell
                cell.configure(with: item, mediaType: mediaType)
                cell.configureSelection(isSelected: isSelected)
                cell.delegate = self
                return cell
            }
        case .list:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ListItemCell", for: indexPath) as! ListItemCell
            cell.configure(with: item, mediaType: mediaType)
            cell.configureSelection(isSelected: isSelected)
            cell.delegate = self
            return cell
        }
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
        } else {
            let item = items[indexPath.item]
            play(url: item.url)
        }
    }

    // MARK: - Swipe Selection

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let location = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }

        if !isSelecting {
            isSelecting = true
            selectedItems.insert(indexPath)
            selectButton.title = "Cancel"
            collectionView.reloadData()
            let deleteButton = UIBarButtonItem(
                title: "Delete",
                style: .plain,
                target: self,
                action: #selector(deleteSelected)
            )
            deleteButton.tintColor = .systemRed
            navigationItem.rightBarButtonItems = [deleteButton]
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelecting else { return }

        let location = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }

        switch gesture.state {
        case .began:
            swipeSelectingState = true
            if !selectedItems.contains(indexPath) {
                selectedItems.insert(indexPath)
                collectionView.reloadItems(at: [indexPath])
            }
        case .changed:
            if !selectedItems.contains(indexPath) {
                selectedItems.insert(indexPath)
                collectionView.reloadItems(at: [indexPath])
            }
        case .ended, .cancelled:
            break
        default:
            break
        }
    }

    // MARK: - IconItemCellDelegate

    func iconItemCellDidTapMenu(_ cell: IconItemCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let item = items[indexPath.item]
        showItemMenu(for: item)
    }

    // MARK: - MediaItemCellDelegate

    func mediaItemCellDidTapMenu(_ cell: MediaItemCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let item = items[indexPath.item]
        showItemMenu(for: item)
    }

    // MARK: - ListItemCellDelegate

    func listItemCellDidTapMenu(_ cell: ListItemCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let item = items[indexPath.item]
        showItemMenu(for: item)
    }

    private func showItemMenu(for item: LocalMediaItem) {
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

        // Group 1: Share
        let shareButton = createShareButton { [weak self] in
            self?.shareItem(item)
        }
        stackView.addArrangedSubview(shareButton)

        // Group 2: File operations (no Download for local files)
        let group2 = createMenuGroup(actions: [
            ("pencil", "Rename", { [weak self] in self?.renameItem(item) }, false),
            ("folder", "Move to", { [weak self] in self?.moveItem(item) }, false),
            ("doc.on.doc", "Copy to", { [weak self] in self?.copyItem(item) }, false),
            ("plus.square.on.square", "Duplicate", { [weak self] in self?.duplicateItem(item) }, false),
            ("trash", "Delete", { [weak self] in self?.confirmDelete(item: item) }, true)
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

    private func createMenuHeader(for item: LocalMediaItem) -> UIView {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12

        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        iconView.preferredSymbolConfiguration = config
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false

        if mediaType == .video {
            iconView.image = UIImage(systemName: "video.fill")
            iconView.tintColor = .systemPurple
        } else {
            iconView.image = UIImage(systemName: "music.note")
            iconView.tintColor = .systemPink
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
        details.append(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
        if let modified = item.modified {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            details.append(formatter.string(from: modified))
        }
        detailLabel.text = details.joined(separator: " • ")
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

    private func shareItem(_ item: LocalMediaItem) {
        let activityVC = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(activityVC, animated: true)
    }

    private func renameItem(_ item: LocalMediaItem) {
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

    private func performRename(item: LocalMediaItem, newName: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let newURL = documentsPath.appendingPathComponent(newName)

        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            loadMedia()
        } catch {
            let alert = UIAlertController(title: "Rename Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func moveItem(_ item: LocalMediaItem) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.directoryURL = item.url.deletingLastPathComponent()
        movingItem = item
        present(picker, animated: true)
    }

    private func copyItem(_ item: LocalMediaItem) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.directoryURL = item.url.deletingLastPathComponent()
        copyingItem = item
        present(picker, animated: true)
    }

    private func duplicateItem(_ item: LocalMediaItem) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseName = (item.name as NSString).deletingPathExtension
        let ext = (item.name as NSString).pathExtension
        var copyName = "\(baseName) copy.\(ext)"
        var copyURL = documentsPath.appendingPathComponent(copyName)
        var counter = 2

        while FileManager.default.fileExists(atPath: copyURL.path) {
            copyName = "\(baseName) copy \(counter).\(ext)"
            copyURL = documentsPath.appendingPathComponent(copyName)
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: item.url, to: copyURL)
            loadMedia()
        } catch {
            let alert = UIAlertController(title: "Duplicate Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func confirmDelete(item: LocalMediaItem) {
        let alert = UIAlertController(
            title: "Delete File?",
            message: item.name,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.delete(item: item)
        })
        present(alert, animated: true)
    }

    private func showInfo(for item: LocalMediaItem) {
        var info = "Name: \(item.name)\n"
        info += "Size: \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))\n"

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
}

extension MediaLibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Handle move operation
        if let item = movingItem, let destDir = urls.first {
            guard destDir.startAccessingSecurityScopedResource() else {
                movingItem = nil
                return
            }
            defer {
                destDir.stopAccessingSecurityScopedResource()
            }

            let destURL = destDir.appendingPathComponent(item.name)
            do {
                try FileManager.default.moveItem(at: item.url, to: destURL)
                loadMedia()
            } catch {
                let alert = UIAlertController(title: "Move Failed", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
            movingItem = nil
            return
        }

        // Handle copy operation
        if let item = copyingItem, let destDir = urls.first {
            guard destDir.startAccessingSecurityScopedResource() else {
                copyingItem = nil
                return
            }
            defer {
                destDir.stopAccessingSecurityScopedResource()
            }

            let destURL = destDir.appendingPathComponent(item.name)
            do {
                try FileManager.default.copyItem(at: item.url, to: destURL)
                let alert = UIAlertController(title: "Copied", message: "File copied to \(destDir.lastPathComponent)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            } catch {
                let alert = UIAlertController(title: "Copy Failed", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
            copyingItem = nil
            return
        }

        // Handle import operation
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for url in urls {
            // Security-scoped resource access
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access security-scoped resource: \(url)")
                continue
            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }

            let destURL = documentsPath.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                print("Error copying file: \(error)")
                DispatchQueue.main.async { [weak self] in
                    let alert = UIAlertController(title: "Import Failed", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
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

// MARK: - MediaItemCell

protocol MediaItemCellDelegate: AnyObject {
    func mediaItemCellDidTapMenu(_ cell: MediaItemCell)
}

final class MediaItemCell: UICollectionViewCell {
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let menuButton = UIButton()
    private let selectionOverlay = UIView()

    weak var delegate: MediaItemCellDelegate?

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

        // Menu button in bottom right corner
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .secondaryLabel
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(menuButton)

        // Selection overlay
        selectionOverlay.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
        selectionOverlay.layer.borderColor = UIColor.systemBlue.cgColor
        selectionOverlay.layer.borderWidth = 2
        selectionOverlay.layer.cornerRadius = 12
        selectionOverlay.isHidden = true
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionOverlay)

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
            detailLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -4),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            menuButton.centerYAnchor.constraint(equalTo: detailLabel.centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            menuButton.widthAnchor.constraint(equalToConstant: 32),
            menuButton.heightAnchor.constraint(equalToConstant: 24),

            selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func menuTapped() {
        delegate?.mediaItemCellDidTapMenu(self)
    }

    func configureSelection(isSelected: Bool) {
        selectionOverlay.isHidden = !isSelected
    }

    func configure(with item: LocalMediaItem, mediaType: MediaType) {
        titleLabel.text = item.name

        // Reset thumbnail
        thumbnailView.image = nil
        thumbnailView.contentMode = .scaleAspectFill

        if let modified = item.modified {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            detailLabel.text = formatter.string(from: modified)
        } else {
            detailLabel.text = nil
        }

        // Generate thumbnail for video files
        if mediaType == .video {
            generateThumbnail(for: item.url)
        } else {
            // Audio: show icon
            thumbnailView.image = UIImage(systemName: "music.note")
            thumbnailView.tintColor = .systemGray3
            thumbnailView.contentMode = .center
        }
    }

    private func generateThumbnail(for url: URL) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 1, preferredTimescale: 600)

        generator.generateCGImageAsynchronously(for: time) { [weak self] cgImage, _, error in
            guard let cgImage = cgImage, error == nil else {
                // Failed: show default icon
                DispatchQueue.main.async {
                    self?.thumbnailView.image = UIImage(systemName: "video.fill")
                    self?.thumbnailView.tintColor = .systemGray3
                    self?.thumbnailView.contentMode = .center
                }
                return
            }

            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self?.thumbnailView.image = image
                self?.thumbnailView.contentMode = .scaleAspectFill
            }
        }
    }
}

// MARK: - IconItemCell

protocol IconItemCellDelegate: AnyObject {
    func iconItemCellDidTapMenu(_ cell: IconItemCell)
}

final class IconItemCell: UICollectionViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let menuButton = UIButton()
    private let selectionOverlay = UIView()

    weak var delegate: IconItemCellDelegate?

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

        // Icon - centered at top, 64x64 like FileItemCell
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
            menuButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4),

            selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func menuTapped() {
        delegate?.iconItemCellDidTapMenu(self)
    }

    func configureSelection(isSelected: Bool) {
        selectionOverlay.isHidden = !isSelected
    }

    func configure(with item: LocalMediaItem, mediaType: MediaType) {
        titleLabel.text = item.name

        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        iconView.preferredSymbolConfiguration = config

        let iconName = mediaType == .video ? "video.fill" : "music.note"
        iconView.image = UIImage(systemName: iconName)

        if mediaType == .video {
            iconView.tintColor = .systemPurple
        } else {
            iconView.tintColor = .systemPink
        }
    }
}

// MARK: - ListItemCell

protocol ListItemCellDelegate: AnyObject {
    func listItemCellDidTapMenu(_ cell: ListItemCell)
}

final class ListItemCell: UICollectionViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let menuButton = UIButton()
    private let selectionOverlay = UIView()

    weak var delegate: ListItemCellDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = .systemBackground

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // Icon on left
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        iconView.preferredSymbolConfiguration = config
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // Title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Detail (size/date)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailLabel)

        // Menu button on right
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .secondaryLabel
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(menuButton)

        // Selection overlay
        selectionOverlay.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        selectionOverlay.isHidden = true
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionOverlay)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 60),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -8),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -8),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            menuButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),

            selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func menuTapped() {
        delegate?.listItemCellDidTapMenu(self)
    }

    func configure(with item: LocalMediaItem, mediaType: MediaType) {
        titleLabel.text = item.name

        var details: [String] = []
        details.append(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
        if let modified = item.modified {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            details.append(formatter.string(from: modified))
        }
        detailLabel.text = details.joined(separator: " • ")

        if mediaType == .video {
            iconView.image = UIImage(systemName: "video.fill")
            iconView.tintColor = .systemPurple
        } else {
            iconView.image = UIImage(systemName: "music.note")
            iconView.tintColor = .systemPink
        }
    }

    func configureSelection(isSelected: Bool) {
        selectionOverlay.isHidden = !isSelected
    }
}
