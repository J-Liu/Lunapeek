// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import UniformTypeIdentifiers

// MARK: - Data Models

struct PlaylistItem: Codable {
    let name: String
    let url: URL
    let addedDate: Date
}

struct PlaylistData: Codable {
    var name: String
    var items: [PlaylistItem]
    let createdDate: Date

    init(name: String) {
        self.name = name
        self.items = []
        self.createdDate = Date()
    }
}

// MARK: - Playlist Manager

class PlaylistManager {
    static let shared = PlaylistManager()

    private let playlistsKey = "SavedPlaylists"
    private var playlists: [PlaylistData] = []

    private init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey),
              let saved = try? JSONDecoder().decode([PlaylistData].self, from: data)
        else {
            // Create default playlists
            playlists = [
                PlaylistData(name: NSLocalizedString("Favorites", comment: "")),
                PlaylistData(name: NSLocalizedString("Recently Played", comment: ""))
            ]
            return
        }
        playlists = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: playlistsKey)
    }

    func getPlaylists() -> [PlaylistData] {
        return playlists
    }

    func createPlaylist(name: String) {
        let playlist = PlaylistData(name: name)
        playlists.append(playlist)
        save()
    }

    func deletePlaylist(at index: Int) {
        guard index < playlists.count else { return }
        playlists.remove(at: index)
        save()
    }

    func renamePlaylist(at index: Int, to name: String) {
        guard index < playlists.count else { return }
        playlists[index].name = name
        save()
    }

    func addItem(to playlistIndex: Int, item: PlaylistItem) {
        guard playlistIndex < playlists.count else { return }
        playlists[playlistIndex].items.append(item)
        save()
    }

    func removeItem(from playlistIndex: Int, itemIndex: Int) {
        guard playlistIndex < playlists.count, itemIndex < playlists[playlistIndex].items.count else { return }
        playlists[playlistIndex].items.remove(at: itemIndex)
        save()
    }

    func getPlaylist(at index: Int) -> PlaylistData? {
        guard index < playlists.count else { return nil }
        return playlists[index]
    }
}

// MARK: - Playlist List View Controller

final class PlaylistViewController: UIViewController {
    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    func languageDidChange() {
        title = NSLocalizedString("Playlist", comment: "")
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private func setupUI() {
        title = NSLocalizedString("Playlist", comment: "")
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(createPlaylist)
        )

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .systemBackground
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PlaylistCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func createPlaylist() {
        let alert = UIAlertController(title: NSLocalizedString("New Playlist", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("Enter playlist name", comment: "")
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("Create", comment: ""), style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            PlaylistManager.shared.createPlaylist(name: name)
            self?.tableView.reloadData()
        })

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }
}

extension PlaylistViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlaylistManager.shared.getPlaylists().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaylistCell", for: indexPath)
        let playlists = PlaylistManager.shared.getPlaylists()
        let playlist = playlists[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = playlist.name
        let itemCount = playlist.items.count
        config.secondaryText = itemCount == 1 ? NSLocalizedString("1 item", comment: "") : String(format: NSLocalizedString("%d items", comment: ""), itemCount)
        config.image = UIImage(systemName: playlist.name == NSLocalizedString("Favorites", comment: "") ? "heart.fill" : "music.note.list")
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let playlists = PlaylistManager.shared.getPlaylists()
        let playlist = playlists[indexPath.row]

        let detailVC = PlaylistDetailViewController(playlistIndex: indexPath.row, playlist: playlist)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let playlists = PlaylistManager.shared.getPlaylists()
            let playlist = playlists[indexPath.row]

            // Don't allow deleting default playlists
            if playlist.name == NSLocalizedString("Favorites", comment: "") || playlist.name == NSLocalizedString("Recently Played", comment: "") {
                let alert = UIAlertController(
                    title: NSLocalizedString("Cannot Delete", comment: ""),
                    message: NSLocalizedString("Default playlists cannot be deleted", comment: ""),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                present(alert, animated: true)
                return
            }

            PlaylistManager.shared.deletePlaylist(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let playlists = PlaylistManager.shared.getPlaylists()
        let playlist = playlists[indexPath.row]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let renameAction = UIAction(title: NSLocalizedString("Rename", comment: ""), image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.renamePlaylist(at: indexPath.row, currentName: playlist.name)
            }

            var children: [UIMenuElement] = [renameAction]

            if playlist.name != NSLocalizedString("Favorites", comment: "") && playlist.name != NSLocalizedString("Recently Played", comment: "") {
                let deleteAction = UIAction(title: NSLocalizedString("Delete", comment: ""), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    PlaylistManager.shared.deletePlaylist(at: indexPath.row)
                    self?.tableView.reloadData()
                }
                children.append(deleteAction)
            }

            return UIMenu(title: "", children: children)
        }
    }

    private func renamePlaylist(at index: Int, currentName: String) {
        let alert = UIAlertController(title: NSLocalizedString("Rename Playlist", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = currentName
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("Rename", comment: ""), style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            PlaylistManager.shared.renamePlaylist(at: index, to: name)
            self?.tableView.reloadData()
        })

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - Playlist Detail View Controller

final class PlaylistDetailViewController: UIViewController {
    private let playlistIndex: Int
    private var playlist: PlaylistData
    private var tableView: UITableView!

    init(playlistIndex: Int, playlist: PlaylistData) {
        self.playlistIndex = playlistIndex
        self.playlist = playlist
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
        if let updated = PlaylistManager.shared.getPlaylist(at: playlistIndex) {
            playlist = updated
            tableView.reloadData()
        }
    }

    private func setupUI() {
        title = playlist.name
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addItem)
        )

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .systemBackground
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ItemCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if playlist.items.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No items yet.\nTap + to add media files."
            emptyLabel.textColor = .secondaryLabel
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(emptyLabel)

            NSLayoutConstraint.activate([
                emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    @objc private func addItem() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video, .audio, .mp3])
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    private func play(item: PlaylistItem) {
        let playerVC = PlayerViewController(url: item.url)
        playerVC.modalPresentationStyle = .fullScreen
        present(playerVC, animated: true)
    }
}

extension PlaylistDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return playlist.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
        let item = playlist.items[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.name

        let ext = (item.name as NSString).pathExtension.lowercased()
        let icon: UIImage?
        switch ext {
        case "mp4", "mov", "avi", "mkv", "webm":
            icon = UIImage(systemName: "video.fill")
        case "mp3", "wav", "flac", "aac", "m4a":
            icon = UIImage(systemName: "music.note")
        default:
            icon = UIImage(systemName: "doc.fill")
        }
        config.image = icon
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = playlist.items[indexPath.row]
        play(item: item)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            PlaylistManager.shared.removeItem(from: playlistIndex, itemIndex: indexPath.row)
            if let updated = PlaylistManager.shared.getPlaylist(at: playlistIndex) {
                playlist = updated
            }
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}

extension PlaylistDetailViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let item = PlaylistItem(
                name: url.lastPathComponent,
                url: url,
                addedDate: Date()
            )
            PlaylistManager.shared.addItem(to: playlistIndex, item: item)
        }

        if let updated = PlaylistManager.shared.getPlaylist(at: playlistIndex) {
            playlist = updated
        }
        tableView.reloadData()
    }
}
