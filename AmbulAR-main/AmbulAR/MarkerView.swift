// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

final class MarkerView: UIView {

    private let circleView = UIView()
    private let label = UILabel()
    private let distanceLabel = UILabel()

    var markerType: MarkerType = .start {
        didSet {
            updateAppearance()
        }
    }

    var debugText: String = "" {
        didSet {
            distanceLabel.text = debugText
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let size: CGFloat = 40

        circleView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        circleView.layer.cornerRadius = size / 2
        circleView.backgroundColor = .systemGreen
        circleView.layer.borderWidth = 3
        circleView.layer.borderColor = UIColor.white.cgColor
        addSubview(circleView)

        label.frame = CGRect(x: -10, y: size + 4, width: size + 20, height: 20)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)

        distanceLabel.frame = CGRect(x: -10, y: size + 24, width: size + 20, height: 16)
        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        distanceLabel.textColor = .systemYellow
        distanceLabel.textAlignment = .center
        addSubview(distanceLabel)

        frame = CGRect(x: 0, y: 0, width: size, height: size + 40)
        updateAppearance()
    }

    private func updateAppearance() {
        circleView.backgroundColor = markerType.color
        label.text = markerType.label
    }
}

extension MarkerType {
    var label: String {
        switch self {
        case .start: return NSLocalizedString("Start Point", comment: "")
        case .pause: return NSLocalizedString("Pause Point", comment: "")
        case .resume: return NSLocalizedString("Resume Point", comment: "")
        case .finish: return NSLocalizedString("Finish Point", comment: "")
        }
    }
}
