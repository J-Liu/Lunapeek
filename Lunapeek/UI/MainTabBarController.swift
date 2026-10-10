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
        setupTabs()
    }

    private func setupTabs() {
        let videoVC = MediaLibraryViewController(mediaType: .video)
        videoVC.tabBarItem = UITabBarItem(
            title: "Video",
            image: UIImage(systemName: "video.fill"),
            tag: 0
        )

        let audioVC = MediaLibraryViewController(mediaType: .audio)
        audioVC.tabBarItem = UITabBarItem(
            title: "Audio",
            image: UIImage(systemName: "music.note.list"),
            tag: 1
        )

        let playlistVC = PlaylistViewController()
        playlistVC.tabBarItem = UITabBarItem(
            title: "Playlist",
            image: UIImage(systemName: "list.bullet.rectangle"),
            tag: 2
        )

        let networkVC = NetworkViewController()
        networkVC.tabBarItem = UITabBarItem(
            title: "Network",
            image: UIImage(systemName: "network"),
            tag: 3
        )

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape.fill"),
            tag: 4
        )

        viewControllers = [
            UINavigationController(rootViewController: videoVC),
            UINavigationController(rootViewController: audioVC),
            UINavigationController(rootViewController: playlistVC),
            UINavigationController(rootViewController: networkVC),
            UINavigationController(rootViewController: settingsVC)
        ]

        tabBar.tintColor = .systemBlue
        tabBar.backgroundColor = .systemBackground
    }
}
