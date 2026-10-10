// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class AboutViewController: UIViewController {

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.text = "AmbulAR"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let linkButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("github.com/J-Liu/AmbulAR", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let copyrightLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Copyright 2026 Jia Liu. All rights reserved."
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        title = NSLocalizedString("About", comment: "")
        view.backgroundColor = .systemBackground

        view.addSubview(titleLabel)
        view.addSubview(linkButton)
        view.addSubview(copyrightLabel)

        linkButton.addTarget(self, action: #selector(openLink), for: .touchUpInside)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            linkButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            linkButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            copyrightLabel.topAnchor.constraint(equalTo: linkButton.bottomAnchor, constant: 30),
            copyrightLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            copyrightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func openLink() {
        if let url = URL(string: "https://github.com/J-Liu/AmbulAR") {
            UIApplication.shared.open(url)
        }
    }
}
