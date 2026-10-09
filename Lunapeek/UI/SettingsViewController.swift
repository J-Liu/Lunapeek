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
        case 0: return 3 // File Browser
        case 1: return 3 // Playback
        case 2: return 2 // Video
        case 3: return 2 // About
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "File Browser"
        case 1: return "Playback"
        case 2: return "Video"
        case 3: return "About"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none

        switch indexPath.section {
        case 0: // File Browser
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Show Hidden Files"
                let toggle = UISwitch()
                toggle.isOn = Settings.shared.showHiddenFiles
                toggle.addTarget(self, action: #selector(showHiddenFilesChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 1:
                cell.textLabel?.text = "Show Non-Media Files"
                let toggle = UISwitch()
                toggle.isOn = Settings.shared.showNonMediaFiles
                toggle.addTarget(self, action: #selector(showNonMediaFilesChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 2:
                cell.textLabel?.text = "Clear Recent Servers"
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case 1: // Playback
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Auto Play Next"
                let toggle = UISwitch()
                toggle.isOn = Settings.shared.autoPlayNext
                toggle.addTarget(self, action: #selector(autoPlayNextChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 1:
                cell.textLabel?.text = "Repeat Mode"
                cell.detailTextLabel?.text = Settings.shared.repeatMode.displayName
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "Background Play"
                let toggle = UISwitch()
                toggle.isOn = Settings.shared.backgroundPlay
                toggle.addTarget(self, action: #selector(backgroundPlayChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            default: break
            }

        case 2: // Video
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Hardware Decode"
                cell.detailTextLabel?.text = Settings.shared.hardwareDecode.displayName
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Default Aspect Ratio"
                cell.detailTextLabel?.text = Settings.shared.defaultAspectRatio.displayName
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case 3: // About
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Version"
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                cell.detailTextLabel?.text = version
            case 1:
                cell.textLabel?.text = "License"
                cell.detailTextLabel?.text = "AGPL-3.0"
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        default: break
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            if indexPath.row == 2 {
                clearRecentServers()
            }
        case 1:
            if indexPath.row == 1 {
                showRepeatModePicker()
            }
        case 2:
            if indexPath.row == 0 {
                showHardwareDecodePicker()
            } else if indexPath.row == 1 {
                showAspectRatioPicker()
            }
        case 3:
            if indexPath.row == 1 {
                showLicense()
            }
        default: break
        }
    }

    // MARK: - Actions

    @objc private func showHiddenFilesChanged(_ sender: UISwitch) {
        Settings.shared.showHiddenFiles = sender.isOn
    }

    @objc private func showNonMediaFilesChanged(_ sender: UISwitch) {
        Settings.shared.showNonMediaFiles = sender.isOn
    }

    @objc private func autoPlayNextChanged(_ sender: UISwitch) {
        Settings.shared.autoPlayNext = sender.isOn
    }

    @objc private func backgroundPlayChanged(_ sender: UISwitch) {
        Settings.shared.backgroundPlay = sender.isOn
    }

    private func clearRecentServers() {
        let alert = UIAlertController(
            title: "Clear Recent Servers",
            message: "This will remove all saved servers. Are you sure?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            SavedServer.save([])
        })
        present(alert, animated: true)
    }

    private func showRepeatModePicker() {
        let alert = UIAlertController(title: "Repeat Mode", message: nil, preferredStyle: .actionSheet)
        for mode in RepeatMode.allCases {
            let isSelected = Settings.shared.repeatMode == mode
            alert.addAction(UIAlertAction(title: mode.displayName + (isSelected ? " ✓" : ""), style: .default) { _ in
                Settings.shared.repeatMode = mode
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func showHardwareDecodePicker() {
        let alert = UIAlertController(title: "Hardware Decode", message: nil, preferredStyle: .actionSheet)
        for mode in HardwareDecode.allCases {
            let isSelected = Settings.shared.hardwareDecode == mode
            alert.addAction(UIAlertAction(title: mode.displayName + (isSelected ? " ✓" : ""), style: .default) { _ in
                Settings.shared.hardwareDecode = mode
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func showAspectRatioPicker() {
        let alert = UIAlertController(title: "Default Aspect Ratio", message: nil, preferredStyle: .actionSheet)
        for ratio in AspectRatio.allCases {
            let isSelected = Settings.shared.defaultAspectRatio == ratio
            alert.addAction(UIAlertAction(title: ratio.displayName + (isSelected ? " ✓" : ""), style: .default) { _ in
                Settings.shared.defaultAspectRatio = ratio
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func showLicense() {
        let vc = UIViewController()
        vc.title = "License"
        vc.view.backgroundColor = .systemBackground

        let textView = UITextView()
        textView.font = .systemFont(ofSize: 12)
        textView.isEditable = false
        textView.text = """
        GNU AFFERO GENERAL PUBLIC LICENSE
        Version 3, 19 November 2007

        Copyright (C) 2026 Jia Liu

        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU Affero General Public License as
        published by the Free Software Foundation, either version 3 of the
        License, or (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU Affero General Public License for more details.

        You should have received a copy of the GNU Affero General Public License
        along with this program.  If not, see <https://www.gnu.org/licenses/>.
        """
        textView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])

        navigationController?.pushViewController(vc, animated: true)
    }
}
