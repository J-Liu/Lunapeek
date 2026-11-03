// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import PulseCycleCore

class ProfileListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var profiles: [WorkoutProfile] { ProfileManager.shared.profiles }

    var onSelect: (() -> Void)?
    var onDismiss: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Profiles")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addProfile)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissVC)
        )

        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onDismiss?()
    }

    @objc private func dismissVC() {
        dismiss(animated: true)
    }

    @objc private func addProfile() {
        let alert = UIAlertController(title: L("New Profile"), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = L("Enter name")
        }
        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("Create"), style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            let current = ProfileManager.shared.currentProfile
            _ = ProfileManager.shared.addProfile(copyFrom: current, name: name)
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return profiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let profile = profiles[indexPath.row]
        cell.textLabel?.text = profile.name
        cell.detailTextLabel?.text = "\(profile.rounds) \(L("rounds")) • \(profile.workSeconds)s \(L("work")) • \(profile.restSeconds)s \(L("rest"))"
        cell.accessoryType = (indexPath.row == ProfileManager.shared.currentProfileIndex) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        ProfileManager.shared.selectProfile(at: indexPath.row)
        onSelect?()
        dismiss(animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return profiles.count > 1
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && profiles.count > 1 {
            ProfileManager.shared.deleteProfile(at: indexPath.row)
            tableView.reloadData()
        }
    }
}
