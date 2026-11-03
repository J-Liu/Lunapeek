// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import CoreBluetooth
import PulseCycleCore

class DeviceManagementViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let heartRateMonitor: HeartRateMonitor

    init(heartRateMonitor: HeartRateMonitor) {
        self.heartRateMonitor = heartRateMonitor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("HRM Devices")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addDevice)
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadData),
            name: NSNotification.Name("DeviceListUpdated"),
            object: nil
        )

        // Listen for connection state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnected),
            name: NSNotification.Name("HeartRateMonitorStateChanged"),
            object: nil
        )
    }

    @objc private func reloadData() {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }

    @objc private func handleDeviceConnected() {
        DispatchQueue.main.async { [weak self] in
            // Dismiss scanning alert when device connects
            if self?.presentedViewController is UIAlertController {
                self?.dismiss(animated: true)
            }
            self?.tableView.reloadData()
        }
    }

    @objc private func addDevice() {
        // Start scanning for new devices with timeout handler
        weak var scanningAlert: UIAlertController?

        heartRateMonitor.startScanning { [weak self] in
            // Timeout handler - dismiss alert and show timeout message
            scanningAlert?.dismiss(animated: true) {
                let timeoutAlert = UIAlertController(
                    title: L("Scan Timeout"),
                    message: L("No heart rate devices found. Please make sure your device is powered on and nearby."),
                    preferredStyle: .alert
                )
                timeoutAlert.addAction(UIAlertAction(title: L("OK"), style: .default))
                self?.present(timeoutAlert, animated: true)
            }
        }

        let alert = UIAlertController(
            title: L("Scanning"),
            message: L("Looking for heart rate devices..."),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel) { [weak self] _ in
            self?.heartRateMonitor.stopScanning()
        })

        scanningAlert = alert
        present(alert, animated: true)
    }

    // MARK: - Table View Data Source

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return DeviceManager.shared.devices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "DeviceCell")
        let device = DeviceManager.shared.devices[indexPath.row]
        let isConnected = heartRateMonitor.isConnectedDevice(uuid: device.uuid)
        let isDefault = device.uuid == DeviceManager.shared.defaultDeviceUUID

        cell.textLabel?.text = device.name

        // Build status text
        if isConnected {
            cell.detailTextLabel?.text = L("Connected")
            cell.detailTextLabel?.textColor = .systemGreen
        } else {
            cell.detailTextLabel?.text = nil
        }

        // Show checkmark for default device
        cell.accessoryType = isDefault ? .checkmark : .none

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let device = DeviceManager.shared.devices[indexPath.row]
        let isConnected = heartRateMonitor.isConnectedDevice(uuid: device.uuid)
        let alert = UIAlertController(
            title: device.name,
            message: nil,
            preferredStyle: .actionSheet
        )

        if !isConnected {
            alert.addAction(UIAlertAction(title: L("Connect"), style: .default) { [weak self] _ in
                self?.heartRateMonitor.connectToDevice(uuid: device.uuid)
                self?.navigationController?.popViewController(animated: true)
            })
        } else {
            alert.addAction(UIAlertAction(title: L("Disconnect"), style: .default) { [weak self] _ in
                self?.heartRateMonitor.disconnect()
            })
        }

        alert.addAction(UIAlertAction(title: L("Remove"), style: .destructive) { [weak self] _ in
            if isConnected {
                self?.heartRateMonitor.disconnect()
            }
            // Find current index by uuid to avoid stale indexPath
            if let index = DeviceManager.shared.devices.firstIndex(where: { $0.uuid == device.uuid }) {
                DeviceManager.shared.removeDevice(at: index)
                DispatchQueue.main.async {
                    self?.tableView.reloadData()
                }
            }
        })

        alert.addAction(UIAlertAction(title: L("Cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.frame ?? .zero
        }

        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let device = DeviceManager.shared.devices[indexPath.row]
            if heartRateMonitor.isConnectedDevice(uuid: device.uuid) {
                heartRateMonitor.disconnect()
            }
            DeviceManager.shared.removeDevice(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}
