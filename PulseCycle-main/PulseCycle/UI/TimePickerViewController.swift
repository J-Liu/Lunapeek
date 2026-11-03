// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit

class TimePickerViewController: UIViewController {
    private let pickerView = UIPickerView()
    private let titleText: String
    private let completion: (Int) -> Void

    // For single wheel (rounds)
    private var singleWheelValues: [Int] = []
    private var initialSingleIndex: Int = 0
    private var isSingleWheel: Bool = false

    // For dual wheel (time)
    private var minutes: [Int] = []
    private var seconds: [Int] = []
    private var initialMinutes: Int = 0
    private var initialSeconds: Int = 0

    // Single wheel initializer
    init(title: String, values: [Int], currentValue: Int, completion: @escaping (Int) -> Void) {
        self.titleText = title
        self.completion = completion
        self.singleWheelValues = values
        self.initialSingleIndex = values.firstIndex(of: currentValue) ?? 0
        self.isSingleWheel = true
        super.init(nibName: nil, bundle: nil)
    }

    // Dual wheel initializer
    init(title: String, currentValue: Int, maxMinutes: Int, completion: @escaping (Int) -> Void) {
        self.titleText = title
        self.completion = completion
        self.isSingleWheel = false

        // Minutes: 0 to maxMinutes
        minutes = Array(0...maxMinutes)

        // Seconds: 0 to 59, step 1
        seconds = Array(0...59)

        // Calculate initial values
        initialMinutes = currentValue / 60
        initialSeconds = currentValue % 60

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // Container
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Picker
        pickerView.delegate = self
        pickerView.dataSource = self
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pickerView)

        if isSingleWheel {
            // Single wheel - no labels needed
            NSLayoutConstraint.activate([
                pickerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                pickerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
            ])
        } else {
            // Dual wheel - add labels
            let minuteLabel = UILabel()
            minuteLabel.text = L("min")
            minuteLabel.font = .systemFont(ofSize: 16)
            minuteLabel.textAlignment = .right
            minuteLabel.translatesAutoresizingMaskIntoConstraints = false

            let secondLabel = UILabel()
            secondLabel.text = L("sec")
            secondLabel.font = .systemFont(ofSize: 16)
            secondLabel.textAlignment = .right
            secondLabel.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(minuteLabel)
            containerView.addSubview(secondLabel)

            NSLayoutConstraint.activate([
                pickerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                pickerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

                minuteLabel.leadingAnchor.constraint(equalTo: pickerView.leadingAnchor, constant: -45),
                minuteLabel.trailingAnchor.constraint(equalTo: pickerView.centerXAnchor, constant: -25),
                minuteLabel.topAnchor.constraint(equalTo: pickerView.topAnchor, constant: 80),

                secondLabel.leadingAnchor.constraint(equalTo: pickerView.centerXAnchor, constant: -100),
                secondLabel.trailingAnchor.constraint(equalTo: pickerView.trailingAnchor, constant: -20),
                secondLabel.topAnchor.constraint(equalTo: pickerView.topAnchor, constant: 80)
            ])
        }

        // Buttons
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle(L("Cancel"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = UIButton(type: .system)
        doneButton.setTitle(L("Done"), for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, doneButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),
            containerView.heightAnchor.constraint(equalToConstant: 300),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            pickerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            pickerView.heightAnchor.constraint(equalToConstant: 180),

            buttonStack.topAnchor.constraint(equalTo: pickerView.bottomAnchor, constant: 8),
            buttonStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            buttonStack.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Set initial values
        if isSingleWheel {
            pickerView.selectRow(initialSingleIndex, inComponent: 0, animated: false)
        } else {
            pickerView.selectRow(initialMinutes, inComponent: 0, animated: false)
            pickerView.selectRow(initialSeconds, inComponent: 1, animated: false)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        if isSingleWheel {
            let selectedValue = singleWheelValues[pickerView.selectedRow(inComponent: 0)]
            completion(selectedValue)
        } else {
            let selectedMinutes = pickerView.selectedRow(inComponent: 0)
            let selectedSeconds = pickerView.selectedRow(inComponent: 1)
            let totalSeconds = selectedMinutes * 60 + selectedSeconds
            completion(totalSeconds)
        }
        dismiss(animated: true)
    }
}

extension TimePickerViewController: UIPickerViewDelegate, UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return isSingleWheel ? 1 : 2
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if isSingleWheel {
            return singleWheelValues.count
        } else {
            return component == 0 ? minutes.count : seconds.count
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if isSingleWheel {
            return "\(singleWheelValues[row])"
        } else {
            if component == 0 {
                return "\(minutes[row])"
            } else {
                return String(format: "%02d", seconds[row])
            }
        }
    }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 44
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        if isSingleWheel {
            return 200
        } else {
            return 150
        }
    }
}
