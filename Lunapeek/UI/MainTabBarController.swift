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
        // Update tab bar items without recreating view controllers
        if let vcs = viewControllers {
            for (index, vc) in vcs.enumerated() {
                let navVC = vc as? UINavigationController
                let rootVC = navVC?.viewControllers.first

                switch index {
                case 0:
                    vc.tabBarItem?.title = NSLocalizedString("Video", comment: "")
                    (rootVC as? MediaLibraryViewController)?.languageDidChange()
                case 1:
                    vc.tabBarItem?.title = NSLocalizedString("Audio", comment: "")
                    (rootVC as? MediaLibraryViewController)?.languageDidChange()
                case 2:
                    vc.tabBarItem?.title = NSLocalizedString("Playlist", comment: "")
                    (rootVC as? PlaylistViewController)?.languageDidChange()
                case 3:
                    vc.tabBarItem?.title = NSLocalizedString("Network", comment: "")
                    (rootVC as? NetworkViewController)?.languageDidChange()
                case 4:
                    vc.tabBarItem?.title = NSLocalizedString("Settings", comment: "")
                    (rootVC as? SettingsViewController)?.languageDidChange()
                default: break
                }
            }
        }
    }

    private func setupTabs() {
        let videoVC = MediaLibraryViewController(mediaType: .video)
        videoVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Video", comment: ""),
            image: UIImage(systemName: "video.fill"),
            tag: 0
        )

        let audioVC = MediaLibraryViewController(mediaType: .audio)
        audioVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Audio", comment: ""),
            image: UIImage(systemName: "music.note.list"),
            tag: 1
        )

        let playlistVC = PlaylistViewController()
        playlistVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Playlist", comment: ""),
            image: UIImage(systemName: "list.bullet.rectangle"),
            tag: 2
        )

        let networkVC = NetworkViewController()
        networkVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Network", comment: ""),
            image: UIImage(systemName: "network"),
            tag: 3
        )

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Settings", comment: ""),
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
