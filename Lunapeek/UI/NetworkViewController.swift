// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class NetworkViewController: UIViewController {
    private var servers: [NetworkServer] = []
    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadServers()
    }

    private func setupUI() {
        title = "Network"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addServer)
        )

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .systemBackground
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ServerCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadServers() {
        // TODO: Load saved servers
        servers = []
        tableView.reloadData()
    }

    @objc private func addServer() {
        let alert = UIAlertController(title: "Add Server", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "SMB/CIFS", style: .default) { [weak self] _ in
            self?.showSMBConfig()
        })

        alert.addAction(UIAlertAction(title: "SFTP", style: .default) { [weak self] _ in
            self?.showSFTPConfig()
        })

        alert.addAction(UIAlertAction(title: "WebDAV", style: .default) { [weak self] _ in
            self?.showWebDAVConfig()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func showSMBConfig() {
        let alert = UIAlertController(title: "SMB Server", message: nil, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "Server Address"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Share Name"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Username (optional)"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Password (optional)"
            textField.isSecureTextEntry = true
        }

        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            // TODO: Save and connect
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showSFTPConfig() {
        let alert = UIAlertController(title: "SFTP Server", message: nil, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "Server Address"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Port (22)"
            textField.keyboardType = .numberPad
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
            // TODO: Save and connect
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showWebDAVConfig() {
        let alert = UIAlertController(title: "WebDAV Server", message: nil, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "URL"
            textField.autocapitalizationType = .none
            textField.keyboardType = .URL
        }

        alert.addTextField { textField in
            textField.placeholder = "Username (optional)"
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Password (optional)"
            textField.isSecureTextEntry = true
        }

        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            // TODO: Save and connect
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

extension NetworkViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return servers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ServerCell", for: indexPath)
        let server = servers[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = server.name
        config.secondaryText = server.address
        config.image = UIImage(systemName: server.type.icon)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // TODO: Browse server files
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            servers.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}

struct NetworkServer {
    let name: String
    let address: String
    let type: ServerType
}

enum ServerType {
    case smb, sftp, webdav

    var icon: String {
        switch self {
        case .smb: return "folder.fill"
        case .sftp: return "terminal.fill"
        case .webdav: return "cloud.fill"
        }
    }
}
