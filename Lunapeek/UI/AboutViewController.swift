// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class AboutViewController: UIViewController {

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        // Load icon from AppStore-1024.png in bundle root
        if let image = UIImage(named: "AppStore-1024") {
            imageView.image = image
        } else if let path = Bundle.main.path(forResource: "AppStore-1024", ofType: "png"),
                  let image = UIImage(contentsOfFile: path) {
            imageView.image = image
        } else {
            imageView.image = UIImage(systemName: "play.circle.fill")
            imageView.tintColor = .systemBlue
        }
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
        label.text = L("Copyright 2026 Jia Liu. All rights reserved.")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let noticeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(L("Notice"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        title = L("About")
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(iconImageView)
        view.addSubview(titleLabel)
        view.addSubview(versionLabel)
        view.addSubview(linkButton)
        view.addSubview(copyrightLabel)
        view.addSubview(noticeButton)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        versionLabel.text = "\(L("Version")) \(version) (\(build))"

        linkButton.addTarget(self, action: #selector(openLink), for: .touchUpInside)
        noticeButton.addTarget(self, action: #selector(showNotice), for: .touchUpInside)

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
            copyrightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            noticeButton.topAnchor.constraint(equalTo: copyrightLabel.bottomAnchor, constant: 16),
            noticeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func openLink() {
        if let url = URL(string: "https://github.com/J-Liu/Lunapeek") {
            UIApplication.shared.open(url)
        }
    }

    @objc private func showNotice() {
        let vc = UIViewController()
        vc.title = L("Notice")
        vc.view.backgroundColor = .systemBackground

        let textView = UITextView()
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(textView)

        let notice = """
        Lunapeek — A gentle player for common formats.
        Copyright 2026 Jia Liu

        This product includes software developed by Jia Liu.

        The original Lunapeek project and its contributors must be credited
        in any redistribution or derivative work. This attribution notice must
        be retained in all copies or substantial portions of the software.
        """

        textView.text = notice

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])

        navigationController?.pushViewController(vc, animated: true)
    }
}
