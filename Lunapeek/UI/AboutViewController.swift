// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class AboutViewController: UIViewController {

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "AppIcon")
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 22
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.text = "Lunapeek"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let versionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let linkButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("github.com/J-Liu/Lunapeek", for: .normal)
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
        label.text = NSLocalizedString("Copyright 2026 Jia Liu. All rights reserved.", comment: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        title = NSLocalizedString("About", comment: "")
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(iconImageView)
        view.addSubview(titleLabel)
        view.addSubview(versionLabel)
        view.addSubview(linkButton)
        view.addSubview(copyrightLabel)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        versionLabel.text = "\(NSLocalizedString("Version", comment: "")) \(version) (\(build))"

        linkButton.addTarget(self, action: #selector(openLink), for: .touchUpInside)

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 120),
            iconImageView.heightAnchor.constraint(equalToConstant: 120),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            linkButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 20),
            linkButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            copyrightLabel.topAnchor.constraint(equalTo: linkButton.bottomAnchor, constant: 30),
            copyrightLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            copyrightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func openLink() {
        if let url = URL(string: "https://github.com/J-Liu/Lunapeek") {
            UIApplication.shared.open(url)
        }
    }
}
