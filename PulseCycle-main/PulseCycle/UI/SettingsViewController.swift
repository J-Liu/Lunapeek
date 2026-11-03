// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import PulseCycleCore

class SettingsViewController: UIViewController {
    var onSave: (() -> Void)?
    var heartRateMonitor: HeartRateMonitor?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var currentColorRow = 0
    private var profile: WorkoutProfile {
        ProfileManager.shared.currentProfile
    }

    private enum Section: Int, CaseIterable {
        case profile
        case devices
        case sound
        case color
        case misc
        case about
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Settings")
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
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

        // Listen for device list changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadDevicesSection),
            name: NSNotification.Name("DeviceListUpdated"),
            object: nil
        )
    }

    @objc private func reloadDevicesSection() {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadSections(IndexSet(integer: Section.devices.rawValue), with: .none)
        }
    }

    @objc private func done() {
        onSave?()
        dismiss(animated: true)
    }
}

extension SettingsViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .profile: return 7
        case .devices: return 1
        case .sound: return 4
        case .color: return 6
        case .misc: return 3
        case .about: return 1
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .profile: return L("Profile")
        case .devices: return L("HRM Devices")
        case .sound: return L("Sound")
        case .color: return L("Color")
        case .misc: return L("Misc")
        case .about: return nil
        case .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none

        switch Section(rawValue: indexPath.section) {
        case .profile:
            configureProfileCell(cell, row: indexPath.row)
        case .devices:
            configureDeviceCell(cell, row: indexPath.row)
        case .sound:
            configureSoundCell(cell, row: indexPath.row)
        case .color:
            configureColorCell(cell, row: indexPath.row)
        case .misc:
            configureMiscCell(cell, row: indexPath.row)
        case .about:
            configureAboutCell(cell)
        case .none:
            break
        }

        return cell
    }

    private func configureProfileCell(_ cell: UITableViewCell, row: Int) {
        switch row {
        case 0:
            cell.textLabel?.text = L("Profile Name")
            cell.detailTextLabel?.text = profile.name
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 1:
            cell.textLabel?.text = L("Rounds")
            cell.detailTextLabel?.text = "\(profile.rounds)"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 2:
            cell.textLabel?.text = L("Work")
            cell.detailTextLabel?.text = formatTime(profile.workSeconds)
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 3:
            cell.textLabel?.text = L("Rest")
            cell.detailTextLabel?.text = formatTime(profile.restSeconds)
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 4:
            cell.textLabel?.text = L("Prepare time")
            cell.detailTextLabel?.text = "\(profile.prepareTime)s"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 5:
            let checkbox = UIButton(type: .custom)
            checkbox.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            checkbox.setImage(UIImage(systemName: profile.warmUpEnabled ? "checkmark.square.fill" : "square"), for: .normal)
            checkbox.tintColor = .systemBlue
            checkbox.tag = 5
            checkbox.addTarget(self, action: #selector(warmUpCheckboxTapped(_:)), for: .touchUpInside)
            cell.accessoryView = checkbox
            cell.textLabel?.text = L("Warm-up")
            cell.detailTextLabel?.text = profile.warmUpEnabled ? formatTime(profile.warmUpSeconds) : L("Disabled")
            cell.selectionStyle = profile.warmUpEnabled ? .default : .none
            cell.isUserInteractionEnabled = true
        case 6:
            let checkbox = UIButton(type: .custom)
            checkbox.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            checkbox.setImage(UIImage(systemName: profile.coolDownEnabled ? "checkmark.square.fill" : "square"), for: .normal)
            checkbox.tintColor = .systemBlue
            checkbox.tag = 6
            checkbox.addTarget(self, action: #selector(coolDownCheckboxTapped(_:)), for: .touchUpInside)
            cell.accessoryView = checkbox
            cell.textLabel?.text = L("Cool-down")
            cell.detailTextLabel?.text = profile.coolDownEnabled ? formatTime(profile.coolDownSeconds) : L("Disabled")
            cell.selectionStyle = profile.coolDownEnabled ? .default : .none
            cell.isUserInteractionEnabled = true
        default:
            break
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func configureDeviceCell(_ cell: UITableViewCell, row: Int) {
        cell.textLabel?.text = L("HRM Devices")
        let deviceCount = DeviceManager.shared.devices.count

        if deviceCount == 0 {
            cell.detailTextLabel?.text = nil
        } else if let defaultDevice = DeviceManager.shared.getDefaultDevice() {
            if deviceCount == 1 {
                cell.detailTextLabel?.text = defaultDevice.name
            } else {
                cell.detailTextLabel?.text = "\(defaultDevice.name) + \(deviceCount - 1) more"
            }
        } else {
            cell.detailTextLabel?.text = "\(deviceCount) devices"
        }

        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
    }

    private func configureSoundCell(_ cell: UITableViewCell, row: Int) {
        let switch_ = UISwitch()
        switch row {
        case 0:
            cell.textLabel?.text = L("Prepare counting sound")
            switch_.isOn = profile.prepareCountingSoundEnabled
            switch_.addTarget(self, action: #selector(prepareCountingSoundToggled(_:)), for: .valueChanged)
        case 1:
            cell.textLabel?.text = L("Start sound")
            switch_.isOn = profile.startSoundEnabled
            switch_.addTarget(self, action: #selector(startSoundToggled(_:)), for: .valueChanged)
        case 2:
            cell.textLabel?.text = L("Ending notify sound")
            switch_.isOn = profile.endingNotifySoundEnabled
            switch_.addTarget(self, action: #selector(endingNotifySoundToggled(_:)), for: .valueChanged)
        case 3:
            cell.textLabel?.text = L("End sound")
            switch_.isOn = profile.endSoundEnabled
            switch_.addTarget(self, action: #selector(endSoundToggled(_:)), for: .valueChanged)
        default:
            break
        }
        cell.accessoryView = switch_
    }

    private func configureColorCell(_ cell: UITableViewCell, row: Int) {
        let names = [L("Work"), L("Rest"), L("Heart Rate"), L("Prepare"), L("Warm Up"), L("Cool Down")]
        let currentColors = [profile.workColor, profile.restColor, profile.heartRateColor, profile.prepareColor, profile.warmUpColor, profile.coolDownColor]

        cell.textLabel?.text = names[row]

        let colorView = UIView()
        colorView.backgroundColor = UIColor(hex: currentColors[row])
        colorView.layer.cornerRadius = 12
        colorView.layer.borderWidth = 1
        colorView.layer.borderColor = UIColor.systemGray4.cgColor
        colorView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        cell.accessoryView = colorView

        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator

        // Add long press gesture for reset
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleColorLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        cell.addGestureRecognizer(longPress)
        cell.tag = row
    }

    private func configureMiscCell(_ cell: UITableViewCell, row: Int) {
        switch row {
        case 0:
            cell.textLabel?.text = L("Theme")
            let currentTheme = ThemeManager.shared.currentTheme
            cell.detailTextLabel?.text = currentTheme.displayName
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 1:
            cell.textLabel?.text = L("Language")
            let currentLang = LanguageManager.shared.currentLanguage
            cell.detailTextLabel?.text = currentLang.displayName
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 2:
            cell.textLabel?.text = L("Voice output")
            let switch_ = UISwitch()
            switch_.isOn = profile.voiceOutputEnabled
            switch_.addTarget(self, action: #selector(voiceOutputToggled(_:)), for: .valueChanged)
            cell.accessoryView = switch_
        default:
            break
        }
    }

    private func configureAboutCell(_ cell: UITableViewCell) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        cell.textLabel?.text = L("About")
        cell.detailTextLabel?.text = version
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
    }

    @objc private func warmUpCheckboxTapped(_ sender: UIButton) {
        var p = profile
        p.warmUpEnabled = !p.warmUpEnabled
        ProfileManager.shared.updateProfile(p)
        tableView.reloadRows(at: [IndexPath(row: 5, section: 0)], with: .none)
    }

    @objc private func coolDownCheckboxTapped(_ sender: UIButton) {
        var p = profile
        p.coolDownEnabled = !p.coolDownEnabled
        ProfileManager.shared.updateProfile(p)
        tableView.reloadRows(at: [IndexPath(row: 6, section: 0)], with: .none)
    }

    @objc private func prepareCountingSoundToggled(_ switch_: UISwitch) {
        var p = profile
        p.prepareCountingSoundEnabled = switch_.isOn
        ProfileManager.shared.updateProfile(p)
    }

    @objc private func startSoundToggled(_ switch_: UISwitch) {
        var p = profile
        p.startSoundEnabled = switch_.isOn
        ProfileManager.shared.updateProfile(p)
    }

    @objc private func endingNotifySoundToggled(_ switch_: UISwitch) {
        var p = profile
        p.endingNotifySoundEnabled = switch_.isOn
        ProfileManager.shared.updateProfile(p)
    }

    @objc private func endSoundToggled(_ switch_: UISwitch) {
        var p = profile
        p.endSoundEnabled = switch_.isOn
        ProfileManager.shared.updateProfile(p)
    }

    @objc private func voiceOutputToggled(_ switch_: UISwitch) {
        var p = profile
        p.voiceOutputEnabled = switch_.isOn
        ProfileManager.shared.updateProfile(p)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == Section.profile.rawValue {
            switch indexPath.row {
            case 0:
                showNameEditor()
            case 1:
                showRoundsPicker(title: L("Rounds"), currentValue: profile.rounds) { [weak self] value in
                    var p = ProfileManager.shared.currentProfile
                    p.rounds = value
                    ProfileManager.shared.updateProfile(p)
                    self?.tableView.reloadRows(at: [IndexPath(row: 1, section: 0)], with: .none)
                }
            case 2:
                showTimePicker(title: L("Work"), currentValue: profile.workSeconds, maxMinutes: 60) { [weak self] value in
                    var p = ProfileManager.shared.currentProfile
                    p.workSeconds = value
                    ProfileManager.shared.updateProfile(p)
                    self?.tableView.reloadRows(at: [IndexPath(row: 2, section: 0)], with: .none)
                }
            case 3:
                showTimePicker(title: L("Rest"), currentValue: profile.restSeconds, maxMinutes: 60) { [weak self] value in
                    var p = ProfileManager.shared.currentProfile
                    p.restSeconds = value
                    ProfileManager.shared.updateProfile(p)
                    self?.tableView.reloadRows(at: [IndexPath(row: 3, section: 0)], with: .none)
                }
            case 4:
                showTimePicker(title: L("Prepare time"), currentValue: profile.prepareTime, maxMinutes: 60) { [weak self] value in
                    var p = ProfileManager.shared.currentProfile
                    p.prepareTime = value
                    ProfileManager.shared.updateProfile(p)
                    self?.tableView.reloadRows(at: [IndexPath(row: 4, section: 0)], with: .none)
                }
            case 5:
                if profile.warmUpEnabled {
                    showTimePicker(title: L("Warm-up"), currentValue: profile.warmUpSeconds, maxMinutes: 60) { [weak self] value in
                        var p = ProfileManager.shared.currentProfile
                        p.warmUpSeconds = value
                        ProfileManager.shared.updateProfile(p)
                        self?.tableView.reloadRows(at: [IndexPath(row: 5, section: 0)], with: .none)
                    }
                }
            case 6:
                if profile.coolDownEnabled {
                    showTimePicker(title: L("Cool-down"), currentValue: profile.coolDownSeconds, maxMinutes: 60) { [weak self] value in
                        var p = ProfileManager.shared.currentProfile
                        p.coolDownSeconds = value
                        ProfileManager.shared.updateProfile(p)
                        self?.tableView.reloadRows(at: [IndexPath(row: 6, section: 0)], with: .none)
                    }
                }
            default:
                break
            }
        } else if indexPath.section == Section.devices.rawValue {
            showDeviceManagement()
        } else if indexPath.section == Section.misc.rawValue && indexPath.row == 0 {
            showThemePicker()
        } else if indexPath.section == Section.misc.rawValue && indexPath.row == 1 {
            showLanguagePicker()
        } else if indexPath.section == Section.color.rawValue {
            showColorPicker(for: indexPath.row)
        } else if indexPath.section == Section.about.rawValue {
            showAbout()
        }
    }

    private func showRoundsPicker(title: String, currentValue: Int, completion: @escaping (Int) -> Void) {
        let values = Array(1...99)
        let picker = TimePickerViewController(title: title, values: values, currentValue: currentValue, completion: completion)
        picker.modalPresentationStyle = .overFullScreen
        picker.modalTransitionStyle = .crossDissolve
        present(picker, animated: true)
    }

    private func showTimePicker(title: String, currentValue: Int, maxMinutes: Int, completion: @escaping (Int) -> Void) {
        let picker = TimePickerViewController(title: title, currentValue: currentValue, maxMinutes: maxMinutes, completion: completion)
        picker.modalPresentationStyle = .overFullScreen
        picker.modalTransitionStyle = .crossDissolve
        present(picker, animated: true)
    }

    private func showNameEditor() {
        let alert = UIAlertController(title: L("Profile Name"), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = ProfileManager.shared.currentProfile.name
            textField.placeholder = L("Enter name")
        }
        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("Done"), style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            var p = ProfileManager.shared.currentProfile
            p.name = name
            ProfileManager.shared.updateProfile(p)
            self?.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
            self?.onSave?()
        })
        present(alert, animated: true)
    }

    private func showDeviceManagement() {
        guard let heartRateMonitor = heartRateMonitor else { return }
        let vc = DeviceManagementViewController(heartRateMonitor: heartRateMonitor)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showThemePicker() {
        let alert = UIAlertController(title: L("Theme"), message: nil, preferredStyle: .actionSheet)

        for theme in Theme.allCases {
            let action = UIAlertAction(title: theme.displayName, style: .default) { [weak self] _ in
                ThemeManager.shared.currentTheme = theme
                self?.tableView.reloadRows(at: [IndexPath(row: 0, section: Section.misc.rawValue)], with: .none)
            }
            if theme == ThemeManager.shared.currentTheme {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.cellForRow(at: IndexPath(row: 0, section: Section.misc.rawValue))?.frame ?? .zero
        }

        present(alert, animated: true)
    }

    private func showLanguagePicker() {
        let alert = UIAlertController(title: L("Language"), message: nil, preferredStyle: .actionSheet)

        for language in Language.allCases {
            let action = UIAlertAction(title: language.displayName, style: .default) { [weak self] _ in
                LanguageManager.shared.applyLanguage(language)
                self?.tableView.reloadData()
                self?.onSave?()
            }
            if language == LanguageManager.shared.currentLanguage {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.cellForRow(at: IndexPath(row: 1, section: Section.misc.rawValue))?.frame ?? .zero
        }

        present(alert, animated: true)
    }

    private func showAbout() {
        let aboutVC = AboutViewController()
        navigationController?.pushViewController(aboutVC, animated: true)
    }

    private func showColorPicker(for row: Int) {
        currentColorRow = row
        let colorPicker = UIColorPickerViewController()
        colorPicker.delegate = self

        let currentColors = [profile.workColor, profile.restColor, profile.heartRateColor, profile.prepareColor, profile.warmUpColor, profile.coolDownColor]
        colorPicker.selectedColor = UIColor(hex: currentColors[row]) ?? .white

        // Add toolbar with reset button
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let resetButton = UIBarButtonItem(title: L("Reset to Default"), style: .plain, target: self, action: #selector(resetColorFromPicker))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissColorPicker))
        toolbar.items = [resetButton, flexibleSpace, doneButton]

        colorPicker.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 44, right: 0)
        colorPicker.view.addSubview(toolbar)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: colorPicker.view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: colorPicker.view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: colorPicker.view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])

        present(colorPicker, animated: true)
    }

    @objc private func resetColorFromPicker() {
        resetColor(for: currentColorRow)
        if let colorPicker = presentedViewController as? UIColorPickerViewController {
            let currentColors = [profile.workColor, profile.restColor, profile.heartRateColor, profile.prepareColor, profile.warmUpColor, profile.coolDownColor]
            colorPicker.selectedColor = UIColor(hex: currentColors[currentColorRow]) ?? .white
        }
    }

    @objc private func dismissColorPicker() {
        dismiss(animated: true)
    }

    private func resetColor(for row: Int) {
        var p = profile
        let defaultColors = ["#FF6B6B", "#E0E0E0", "#FF8A80", "#FFAAAA", "#FF8888", "#E8A0A0"]

        switch row {
        case 0:
            p.workColor = defaultColors[0]
        case 1:
            p.restColor = defaultColors[1]
        case 2:
            p.heartRateColor = defaultColors[2]
        case 3:
            p.prepareColor = defaultColors[3]
        case 4:
            p.warmUpColor = defaultColors[4]
        case 5:
            p.coolDownColor = defaultColors[5]
        default:
            break
        }

        ProfileManager.shared.updateProfile(p)
        tableView.reloadRows(at: [IndexPath(row: row, section: Section.color.rawValue)], with: .none)
        onSave?()
    }

    @objc private func handleColorLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let cell = gesture.view as? UITableViewCell else { return }

        let row = cell.tag
        let colorNames = [L("Work"), L("Rest"), L("Heart Rate"), L("Prepare"), L("Warm Up"), L("Cool Down")]
        let alert = UIAlertController(title: colorNames[row], message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: L("Reset to Default"), style: .default) { [weak self] _ in
            self?.resetColor(for: row)
        })

        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(alert, animated: true)
    }
}

extension SettingsViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        let row = currentColorRow
        let hex = viewController.selectedColor.toHexString()

        var p = profile
        switch row {
        case 0:
            p.workColor = hex
        case 1:
            p.restColor = hex
        case 2:
            p.heartRateColor = hex
        case 3:
            p.prepareColor = hex
        case 4:
            p.warmUpColor = hex
        case 5:
            p.coolDownColor = hex
        default:
            break
        }

        ProfileManager.shared.updateProfile(p)
        tableView.reloadRows(at: [IndexPath(row: row, section: Section.color.rawValue)], with: .none)
        onSave?()
    }
}
