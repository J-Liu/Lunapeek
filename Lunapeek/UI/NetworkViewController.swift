// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import Foundation
import UIKit

final class NetworkViewController: UIViewController {
    private var discoveredServers: [NetworkServer] = []
    private var savedServers: [SavedServer] = []
    private var isScanning = false
    private var scanTimer: Timer?
    private var smbBrowser: NetServiceBrowser?
    private var sftpBrowser: NetServiceBrowser?

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.backgroundColor = .systemBackground
        tv.delegate = self
        tv.dataSource = self
        tv.register(ServerCell.self, forCellReuseIdentifier: "ServerCell")
        tv.register(ScanningCell.self, forCellReuseIdentifier: "ScanningCell")
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSavedServers()
        startDiscovery()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDiscovery()
    }

    private func setupUI() {
        title = "Network"
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addManual)
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refresh)
        )

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadSavedServers() {
        savedServers = SavedServer.load()
        tableView.reloadData()
    }

    private func startDiscovery() {
        isScanning = true
        tableView.reloadData()

        discoverSMBServers()
        discoverSFTPServers()

        scanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.stopDiscovery()
        }
    }

    private func stopDiscovery() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        tableView.reloadData()
    }

    private func discoverSMBServers() {
        smbBrowser = NetServiceBrowser()
        smbBrowser?.delegate = self
        smbBrowser?.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")

        // Also try _afpovertcp for macOS file sharing
        let afpBrowser = NetServiceBrowser()
        afpBrowser.delegate = self
        afpBrowser.searchForServices(ofType: "_afpovertcp._tcp.", inDomain: "local.")
        objc_setAssociatedObject(self, &afpBrowserKey, afpBrowser, .OBJC_ASSOCIATION_RETAIN)
    }

    private func discoverSFTPServers() {
        sftpBrowser = NetServiceBrowser()
        sftpBrowser?.delegate = self
        sftpBrowser?.searchForServices(ofType: "_sftp-ssh._tcp.", inDomain: "local.")

        // Also try _ssh for standard SSH
        let sshBrowser = NetServiceBrowser()
        sshBrowser.delegate = self
        sshBrowser.searchForServices(ofType: "_ssh._tcp.", inDomain: "local.")
        objc_setAssociatedObject(self, &sshBrowserKey, sshBrowser, .OBJC_ASSOCIATION_RETAIN)
    }

    @objc private func refresh() {
        discoveredServers.removeAll()
        startDiscovery()
    }

    @objc private func addManual() {
        let alert = UIAlertController(title: "Add Server", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "SMB/CIFS", style: .default) { [weak self] _ in
            self?.showManualConfig(type: .smb)
        })

        alert.addAction(UIAlertAction(title: "SFTP/SSH", style: .default) { [weak self] _ in
            self?.showManualConfig(type: .sftp)
        })

        alert.addAction(UIAlertAction(title: "WebDAV", style: .default) { [weak self] _ in
            self?.showManualConfig(type: .webdav)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
        }
        present(alert, animated: true)
    }

    private func showManualConfig(type: ServerType) {
        let title: String
        switch type {
        case .smb: title = "SMB Server"
        case .sftp: title = "SFTP Server"
        case .webdav: title = "WebDAV Server"
        }

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "Host"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }

        if type == .sftp {
            alert.addTextField { textField in
                textField.placeholder = "Port (22)"
                textField.keyboardType = .numberPad
                textField.text = "22"
            }
        }

        alert.addTextField { textField in
            textField.placeholder = "Username"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }

        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            let host = alert.textFields?.first?.text ?? ""
            let username = alert.textFields?.first(where: { $0.placeholder?.contains("Username") == true })?.text ?? ""
            let password = alert.textFields?.first(where: { $0.placeholder == "Password" })?.text ?? ""
            var port: Int? = nil
            if type == .sftp {
                port = Int(alert.textFields?.first(where: { $0.placeholder?.contains("Port") == true })?.text ?? "22")
            }

            self?.connectWithCredentials(
                host: host,
                share: nil,
                type: type,
                username: username,
                password: password,
                port: port
            )
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func connect(to server: NetworkServer) {
        if let saved = savedServers.first(where: { $0.address == server.address }) {
            connectWithCredentials(
                host: saved.address,
                share: saved.share,
                type: saved.type,
                username: saved.username,
                password: saved.password,
                port: saved.port
            )
            return
        }
        showCredentialPrompt(for: server)
    }

    private func showCredentialPrompt(for server: NetworkServer) {
        let title: String
        switch server.type {
        case .smb: title = "SMB Login"
        case .sftp: title = "SFTP Login"
        case .webdav: title = "WebDAV Login"
        }

        let alert = UIAlertController(title: title, message: server.address, preferredStyle: .alert)

        if server.type == .sftp {
            alert.addTextField { textField in
                textField.placeholder = "Port"
                textField.text = "\(server.port ?? 22)"
                textField.keyboardType = .numberPad
            }
        }

        alert.addTextField { textField in
            textField.placeholder = "Username"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }

        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            let username = alert.textFields?.first(where: { $0.placeholder == "Username" })?.text ?? ""
            let password = alert.textFields?.first(where: { $0.placeholder == "Password" })?.text ?? ""
            var port: Int? = nil
            if server.type == .sftp {
                port = Int(alert.textFields?.first(where: { $0.placeholder == "Port" })?.text ?? "22")
            }

            self?.connectWithCredentials(
                host: server.address,
                share: nil,
                type: server.type,
                username: username,
                password: password,
                port: port
            )
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func connectWithCredentials(
        host: String,
        share: String?,
        type: ServerType,
        username: String,
        password: String,
        port: Int?
    ) {
        let loading = UIAlertController(title: "Connecting...", message: nil, preferredStyle: .alert)
        present(loading, animated: true)

        Task { [weak self] in
            guard let self else { return }

            if type == .smb {
                // If share is already known (from saved server), connect directly
                if let share = share, !share.isEmpty {
                    await MainActor.run {
                        loading.dismiss(animated: true) { [weak self] in
                            self?.saveAndBrowse(
                                host: host,
                                share: share,
                                type: type,
                                username: username,
                                password: password,
                                port: port
                            )
                        }
                    }
                    return
                }

                // Otherwise, discover shares
                do {
                    let client = SMBClientWrapper()
                    try await client.login(host: host, port: port ?? 445, username: username, password: password, domain: nil)

                    let shares = try await client.listShares()
                    let diskShares = shares.filter { !$0.name.hasSuffix("$") }

                    await MainActor.run {
                        loading.dismiss(animated: true) { [weak self] in
                            guard let self else { return }
                            if diskShares.isEmpty {
                                let alert = UIAlertController(
                                    title: "No Shares Found",
                                    message: "No accessible shares on this server",
                                    preferredStyle: .alert
                                )
                                alert.addAction(UIAlertAction(title: "OK", style: .default))
                                present(alert, animated: true)
                            } else if diskShares.count == 1 {
                                self.saveAndBrowse(
                                    host: host,
                                    share: diskShares[0].name,
                                    type: type,
                                    username: username,
                                    password: password,
                                    port: port
                                )
                            } else {
                                self.showSharePicker(
                                    host: host,
                                    shares: diskShares,
                                    type: type,
                                    username: username,
                                    password: password,
                                    port: port
                                )
                            }
                        }
                    }

                    await client.disconnect()
                } catch {
                    await MainActor.run {
                        loading.dismiss(animated: true) { [weak self] in
                            guard let self else { return }
                            let alert = UIAlertController(
                                title: "Connection Failed",
                                message: error.localizedDescription,
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            present(alert, animated: true)
                        }
                    }
                }
            } else {
                // For SFTP/WebDAV: connect directly
                try? await Task.sleep(nanoseconds: 500_000_000)

                await MainActor.run {
                    loading.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        self.saveAndBrowse(
                            host: host,
                            share: share,
                            type: type,
                            username: username,
                            password: password,
                            port: port
                        )
                    }
                }
            }
        }
    }

    private func showSharePicker(
        host: String,
        shares: [SMBShare],
        type: ServerType,
        username: String,
        password: String,
        port: Int?
    ) {
        let alert = UIAlertController(title: "Select Share", message: nil, preferredStyle: .actionSheet)

        for share in shares {
            let title = share.comment.isEmpty ? share.name : "\(share.name) - \(share.comment)"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.saveAndBrowse(
                    host: host,
                    share: share.name,
                    type: type,
                    username: username,
                    password: password,
                    port: port
                )
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func saveAndBrowse(
        host: String,
        share: String?,
        type: ServerType,
        username: String,
        password: String,
        port: Int?
    ) {
        let saved = SavedServer(
            name: host,
            address: host,
            share: share,
            type: type,
            username: username,
            password: password,
            port: port
        )

        // Only add if not already saved
        if savedServers.first(where: { $0.address == host && $0.share == share }) == nil {
            savedServers.append(saved)
            SavedServer.save(savedServers)
            tableView.reloadData()
        }

        browseFiles(server: saved)
    }

    private func browseFiles(server: SavedServer) {
        let browserVC = RemoteFileBrowserViewController(server: server)
        navigationController?.pushViewController(browserVC, animated: true)
    }

    private func removeServer(at index: Int) {
        savedServers.remove(at: index)
        SavedServer.save(savedServers)
        tableView.reloadData()
    }
}

private var smbBrowserKey: UInt8 = 0
private var sftpBrowserKey: UInt8 = 0

private var afpBrowserKey: UInt8 = 0
private var sshBrowserKey: UInt8 = 0

extension NetworkViewController: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        print("Discovery error: \(errorDict)")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var type: ServerType?

        if sender.type.contains("smb") {
            type = .smb
        } else if sender.type.contains("sftp") || sender.type.contains("ssh") {
            type = .sftp
        } else if sender.type.contains("afpovertcp") {
            type = .smb  // Treat AFP as file server
        }

        guard let type = type else { return }

        let address = resolveAddress(for: sender)

        let server = NetworkServer(
            name: sender.name,
            address: address,
            type: type,
            port: sender.port
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.discoveredServers.contains(where: { $0.address == address }) {
                self.discoveredServers.append(server)
                self.tableView.reloadData()
            }
        }
    }

    private func resolveAddress(for service: NetService) -> String {
        guard let addresses = service.addresses, !addresses.isEmpty else {
            return service.name
        }

        for data in addresses {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            data.withUnsafeBytes { ptr in
                if let addr = ptr.baseAddress {
                    let result = getnameinfo(
                        addr.assumingMemoryBound(to: sockaddr.self),
                        socklen_t(data.count),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let ip = String(cString: hostname)
                        // Prefer IPv4
                        if !ip.contains(":") {
                            return
                        }
                    }
                }
            }
            let ip = String(cString: hostname)
            if !ip.isEmpty {
                return ip
            }
        }

        return service.name
    }
}

extension NetworkViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        var sections = 1
        if !savedServers.isEmpty { sections += 1 }
        if !discoveredServers.isEmpty || isScanning { sections += 1 }
        return sections
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let hasSaved = !savedServers.isEmpty
        let hasDiscovered = !discoveredServers.isEmpty || isScanning

        if hasSaved && section == 0 { return "Saved Servers" }
        if hasSaved && hasDiscovered && section == 1 { return "Discovered" }
        if !hasSaved && hasDiscovered && section == 0 { return "Discovered" }
        return nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let hasSaved = !savedServers.isEmpty
        let hasDiscovered = !discoveredServers.isEmpty || isScanning

        if hasSaved && section == 0 { return savedServers.count }
        if hasSaved && hasDiscovered && section == 1 {
            if isScanning && discoveredServers.isEmpty { return 1 }
            return discoveredServers.count
        }
        if !hasSaved && hasDiscovered && section == 0 {
            if isScanning && discoveredServers.isEmpty { return 1 }
            return discoveredServers.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let hasSaved = !savedServers.isEmpty
        let hasDiscovered = !discoveredServers.isEmpty || isScanning

        // Scanning indicator
        if hasSaved && hasDiscovered && indexPath.section == 1 && isScanning && discoveredServers.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ScanningCell", for: indexPath) as! ScanningCell
            cell.configure()
            return cell
        }
        if !hasSaved && hasDiscovered && indexPath.section == 0 && isScanning && discoveredServers.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ScanningCell", for: indexPath) as! ScanningCell
            cell.configure()
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ServerCell", for: indexPath) as! ServerCell

        if hasSaved && indexPath.section == 0 {
            let server = savedServers[indexPath.row]
            cell.configure(with: server.name, address: server.address, type: server.type, isSaved: true)
        } else {
            let server = discoveredServers[indexPath.row]
            cell.configure(with: server.name, address: server.address, type: server.type, isSaved: false)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let hasSaved = !savedServers.isEmpty

        if hasSaved && indexPath.section == 0 {
            let server = savedServers[indexPath.row]
            connectWithCredentials(
                host: server.address,
                share: server.share,
                type: server.type,
                username: server.username,
                password: server.password,
                port: server.port
            )
        } else {
            let server = discoveredServers[indexPath.row]
            connect(to: server)
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let hasSaved = !savedServers.isEmpty

        if hasSaved && indexPath.section == 0 && editingStyle == .delete {
            removeServer(at: indexPath.row)
        }
    }
}

struct NetworkServer {
    let name: String
    let address: String
    let type: ServerType
    let port: Int?
}

struct SavedServer: Codable {
    let name: String
    let address: String
    let share: String?
    let type: ServerType
    let username: String
    let password: String
    let port: Int?

    static func load() -> [SavedServer] {
        guard let data = UserDefaults.standard.data(forKey: "SavedServers"),
              let servers = try? JSONDecoder().decode([SavedServer].self, from: data)
        else { return [] }
        return servers
    }

    static func save(_ servers: [SavedServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: "SavedServers")
    }
}

enum ServerType: String, Codable {
    case smb, sftp, webdav

    var icon: String {
        switch self {
        case .smb: return "folder.fill"
        case .sftp: return "terminal.fill"
        case .webdav: return "cloud.fill"
        }
    }
}

final class ServerCell: UITableViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let savedBadge = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        iconView.tintColor = .systemBlue
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        savedBadge.image = UIImage(systemName: "checkmark.circle.fill")
        savedBadge.tintColor = .systemGreen
        savedBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(savedBadge)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: savedBadge.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: savedBadge.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            savedBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            savedBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            savedBadge.widthAnchor.constraint(equalToConstant: 20),
            savedBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func configure(with name: String, address: String, type: ServerType, isSaved: Bool) {
        iconView.image = UIImage(systemName: type.icon)
        titleLabel.text = name
        subtitleLabel.text = address
        savedBadge.isHidden = !isSaved
    }
}

final class ScanningCell: UITableViewCell {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)

        label.text = "Scanning for servers..."
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -60),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure() {
        spinner.startAnimating()
    }
}
