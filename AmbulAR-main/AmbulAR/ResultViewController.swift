// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class ResultViewController: UIViewController {

    var totalDistance: Float = 0
    var unit: DistanceUnit = .meters

    private let distanceLabel = UILabel()
    private var unitSegmentedControl: UISegmentedControl!
    private let doneButton = UIButton(type: .system)
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        updateDistanceDisplay()
    }

    private func setupView() {
        view.backgroundColor = .systemBackground

        unitSegmentedControl = UISegmentedControl(items: DistanceUnit.allCases.map { $0.localizedName })
        unitSegmentedControl.selectedSegmentIndex = DistanceUnit.allCases.firstIndex(of: unit) ?? 0

        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.text = NSLocalizedString("Tracking Complete", comment: "")
        titleLabel.textAlignment = .center
        stackView.addArrangedSubview(titleLabel)

        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        distanceLabel.textAlignment = .center
        stackView.addArrangedSubview(distanceLabel)

        let unitLabel = UILabel()
        unitLabel.font = .systemFont(ofSize: 16, weight: .medium)
        unitLabel.text = NSLocalizedString("Display Unit", comment: "")
        stackView.addArrangedSubview(unitLabel)

        unitSegmentedControl.addTarget(self, action: #selector(unitChanged), for: .valueChanged)
        stackView.addArrangedSubview(unitSegmentedControl)

        doneButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        doneButton.setTitle(NSLocalizedString("Done", comment: ""), for: .normal)
        doneButton.backgroundColor = .systemBlue
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.layer.cornerRadius = 12
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),

            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            doneButton.widthAnchor.constraint(equalToConstant: 150),
            doneButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func updateDistanceDisplay() {
        distanceLabel.text = unit.format(totalDistance)
    }

    @objc private func unitChanged() {
        unit = DistanceUnit.allCases[unitSegmentedControl.selectedSegmentIndex]
        updateDistanceDisplay()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
