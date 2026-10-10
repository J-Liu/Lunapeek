// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class SettingsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let okButton = UIButton(type: .system)

    private let languages = AppLanguage.allCases
    private let units = DistanceUnit.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupObservers()
    }

    private func setupView() {
        title = NSLocalizedString("Settings", comment: "")
        navigationController?.navigationBar.prefersLargeTitles = false

        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        okButton.setTitle(NSLocalizedString("Done", comment: ""), for: .normal)
        okButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        okButton.backgroundColor = .systemBlue
        okButton.setTitleColor(.white, for: .normal)
        okButton.layer.cornerRadius = 12
        okButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(okButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            okButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            okButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            okButton.widthAnchor.constraint(equalToConstant: 150),
            okButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshUI),
            name: LanguageManager.languageChangedNotification,
            object: nil
        )
    }

    @objc private func refreshUI() {
        title = NSLocalizedString("Settings", comment: "")
        okButton.setTitle(NSLocalizedString("Done", comment: ""), for: .normal)
        tableView.reloadData()
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return NSLocalizedString("Language", comment: "")
        case 1: return NSLocalizedString("Display Unit", comment: "")
        case 2: return NSLocalizedString("Hand Preference", comment: "")
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return languages.count
        case 1: return units.count
        case 2: return 2
        case 3: return 1
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
            ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")

        switch indexPath.section {
        case 0:
            let language = languages[indexPath.row]
            cell.textLabel?.text = language.displayName
            cell.accessoryType = LanguageManager.shared.currentLanguage == language ? .checkmark : .none
        case 1:
            let unit = units[indexPath.row]
            cell.textLabel?.text = unit.localizedName
            cell.accessoryType = UserDefaults.standard.string(forKey: "SelectedUnit") == unit.rawValue ? .checkmark : .none
        case 2:
            let isRightHanded = indexPath.row == 0
            cell.textLabel?.text = isRightHanded ? NSLocalizedString("Right-handed", comment: "") : NSLocalizedString("Left-handed", comment: "")
            let currentValue = UserDefaults.standard.object(forKey: "RightHanded") as? Bool ?? true
            cell.accessoryType = currentValue == isRightHanded ? .checkmark : .none
        case 3:
            cell.textLabel?.text = NSLocalizedString("About", comment: "")
            cell.accessoryType = .disclosureIndicator
        default:
            break
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            let selectedLanguage = languages[indexPath.row]
            LanguageManager.shared.currentLanguage = selectedLanguage
        case 1:
            let selectedUnit = units[indexPath.row]
            UserDefaults.standard.set(selectedUnit.rawValue, forKey: "SelectedUnit")
            NotificationCenter.default.post(name: .unitChanged, object: nil)
        case 2:
            let isRightHanded = indexPath.row == 0
            UserDefaults.standard.set(isRightHanded, forKey: "RightHanded")
            NotificationCenter.default.post(name: .handPreferenceChanged, object: nil)
        case 3:
            navigationController?.pushViewController(AboutViewController(), animated: true)
        default:
            break
        }

        tableView.reloadData()
    }
}

extension Notification.Name {
    static let unitChanged = Notification.Name("UnitChangedNotification")
    static let handPreferenceChanged = Notification.Name("HandPreferenceChangedNotification")
}
