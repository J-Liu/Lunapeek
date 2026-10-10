// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageChanged,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        // Recreate tabs to apply new language
        // This is the simplest way to ensure all UI elements are updated
        setupTabs()
    }

    private func setupTabs() {
        let videoVC = MediaLibraryViewController(mediaType: .video)
        let audioVC = MediaLibraryViewController(mediaType: .audio)
        let playlistVC = PlaylistViewController()
        let networkVC = NetworkViewController()
        let settingsVC = SettingsViewController()

        let videoNav = UINavigationController(rootViewController: videoVC)
        let audioNav = UINavigationController(rootViewController: audioVC)
        let playlistNav = UINavigationController(rootViewController: playlistVC)
        let networkNav = UINavigationController(rootViewController: networkVC)
        let settingsNav = UINavigationController(rootViewController: settingsVC)

        videoNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Video", comment: ""),
            image: UIImage(systemName: "video.fill"),
            tag: 0
        )
        audioNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Audio", comment: ""),
            image: UIImage(systemName: "music.note.list"),
            tag: 1
        )
        playlistNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Playlist", comment: ""),
            image: UIImage(systemName: "list.bullet.rectangle"),
            tag: 2
        )
        networkNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Network", comment: ""),
            image: UIImage(systemName: "network"),
            tag: 3
        )
        settingsNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Settings", comment: ""),
            image: UIImage(systemName: "gearshape.fill"),
            tag: 4
        )

        viewControllers = [videoNav, audioNav, playlistNav, networkNav, settingsNav]

        tabBar.tintColor = .systemBlue
        tabBar.backgroundColor = .systemBackground
    }
}
