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
        return 5
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4 // File Browser
        case 1: return 4 // Playback
        case 2: return 1 // Video (only aspect ratio now)
        case 3: return 1 // Language
        case 4: return 2 // About
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "File Browser"
        case 1: return "Playback"
        case 2: return "Video"
        case 3: return "Language"
        case 4: return "About"
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
                cell.textLabel?.text = "Show Thumbnails"
                let toggle = UISwitch()
                toggle.isOn = Settings.shared.showThumbnails
                toggle.addTarget(self, action: #selector(showThumbnailsChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 3:
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
                cell.textLabel?.text = "Audio Background Play"
                let toggle = UISwitch()
                toggle.isOn = Settings.shared.backgroundPlay
                toggle.addTarget(self, action: #selector(backgroundPlayChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 3:
                cell.textLabel?.text = "Exit Behavior"
                cell.detailTextLabel?.text = Settings.shared.exitBehavior.displayName
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case 2: // Video
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Default Aspect Ratio"
                cell.detailTextLabel?.text = Settings.shared.defaultAspectRatio.displayName
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            default: break
            }

        case 3: // Language
            cell.textLabel?.text = "Language"
            cell.detailTextLabel?.text = Settings.shared.language.displayName
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator

        case 4: // About
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
            if indexPath.row == 3 {
                clearRecentServers()
            }
        case 1:
            if indexPath.row == 1 {
                showRepeatModePicker()
            } else if indexPath.row == 3 {
                showExitBehaviorPicker()
            }
        case 2:
            if indexPath.row == 0 {
                showAspectRatioPicker()
            }
        case 3:
            showLanguagePicker()
        case 4:
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

    @objc private func showThumbnailsChanged(_ sender: UISwitch) {
        Settings.shared.showThumbnails = sender.isOn
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

    private func showPicker(title: String, message: String? = nil, items: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        for (index, item) in items.enumerated() {
            let isSelected = index == selectedIndex
            alert.addAction(UIAlertAction(title: item + (isSelected ? " ✓" : ""), style: .default) { _ in
                onSelect(index)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showRepeatModePicker() {
        let items = RepeatMode.allCases.map { $0.displayName }
        let selectedIndex = RepeatMode.allCases.firstIndex(of: Settings.shared.repeatMode) ?? 0
        showPicker(title: "Repeat Mode", items: items, selectedIndex: selectedIndex) { index in
            Settings.shared.repeatMode = RepeatMode.allCases[index]
            self.tableView.reloadData()
        }
    }

    private func showExitBehaviorPicker() {
        let items = ExitBehavior.allCases.map { $0.displayName }
        let selectedIndex = ExitBehavior.allCases.firstIndex(of: Settings.shared.exitBehavior) ?? 0
        showPicker(title: "Exit Behavior", message: "What happens when you leave during video playback", items: items, selectedIndex: selectedIndex) { index in
            Settings.shared.exitBehavior = ExitBehavior.allCases[index]
            self.tableView.reloadData()
        }
    }

    private func showAspectRatioPicker() {
        let items = AspectRatio.allCases.map { $0.displayName }
        let selectedIndex = AspectRatio.allCases.firstIndex(of: Settings.shared.defaultAspectRatio) ?? 0
        showPicker(title: "Default Aspect Ratio", items: items, selectedIndex: selectedIndex) { index in
            Settings.shared.defaultAspectRatio = AspectRatio.allCases[index]
            self.tableView.reloadData()
        }
    }

    private func showLanguagePicker() {
        let items = Language.allCases.map { $0.displayName }
        let selectedIndex = Language.allCases.firstIndex(of: Settings.shared.language) ?? 0
        showPicker(title: "Language", items: items, selectedIndex: selectedIndex) { index in
            Settings.shared.language = Language.allCases[index]
            self.tableView.reloadData()
        }
    }

    private func showLicense() {
        let vc = UIViewController()
        vc.title = "License"
        vc.view.backgroundColor = .systemBackground

        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = .link
        textView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(textView)

        // Load license text with clickable link
        let licenseSummary = """
        GNU AFFERO GENERAL PUBLIC LICENSE
        Version 3, 19 November 2007

        Copyright (C) 2007 Free Software Foundation, Inc.

        Additional Permission under Section 7

        As an additional permission under section 7, you are allowed to distribute
        the software through an app store, even if that store has restrictive terms
        and conditions that are incompatible with the AGPL, provided that the source
        is also available under the AGPL with or without this permission through a
        channel without those restrictive terms and conditions.

        Copyright (C) 2026 Jia Liu

        Full license text:
        https://github.com/J-Liu/Lunapeek/blob/main/LICENSE
        """

        textView.text = licenseSummary

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])

        navigationController?.pushViewController(vc, animated: true)
    }
}
