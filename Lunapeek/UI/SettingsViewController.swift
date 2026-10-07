// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class SettingsViewController: UIViewController {
    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        title = "Settings"
        view.backgroundColor = .systemBackground

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .systemBackground
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3 // Playback
        case 1: return 2 // Video
        case 2: return 2 // Audio
        case 3: return 2 // About
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Playback"
        case 1: return "Video"
        case 2: return "Audio"
        case 3: return "About"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)

        switch indexPath.section {
        case 0: // Playback
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Auto Play Next"
                cell.accessoryType = .checkmark
            case 1:
                cell.textLabel?.text = "Repeat Mode"
                cell.detailTextLabel?.text = "Off"
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "Background Play"
                cell.accessoryType = .checkmark
            default: break
            }

        case 1: // Video
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Hardware Decode"
                cell.detailTextLabel?.text = "Auto"
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Default Aspect Ratio"
                cell.detailTextLabel?.text = "Fit"
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case 2: // Audio
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Audio Output"
                cell.detailTextLabel?.text = "Speakers"
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Equalizer"
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case 3: // About
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Version"
                cell.detailTextLabel?.text = "1.0.0"
            case 1:
                cell.textLabel?.text = "License"
                cell.detailTextLabel?.text = "AGPL-3.0"
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        default: break
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // TODO: Handle selection
    }
}
