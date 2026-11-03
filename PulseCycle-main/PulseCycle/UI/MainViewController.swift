// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import UIKit
import PulseCycleCore

class MainViewController: UIViewController, IntervalEngineDelegate, HeartRateMonitorDelegate {
    private let headerView = UIView()
    private let workLabel = UILabel()
    private let workTimeLabel = UILabel()
    private let profileLabel = UILabel()
    private let restLabel = UILabel()
    private let restTimeLabel = UILabel()

    private let timeLabel = UILabel()
    private let roundLabel = UILabel()

    private let heartRateContainer = UIView()
    private let heartRateLabel = UILabel()
    private let connectionLabel = UILabel()
    private let connectionStackView = UIStackView()
    private let addButton = UIButton(type: .system)
    private var isConnected = false
    private var connectedDeviceName: String?

    private let opView = UIView()
    private let goButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)

    private var engine: IntervalEngine!
    private let heartRateMonitor: HeartRateMonitor
    private var backgroundTimestamp: Date?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private var isRunning = false
    private var hasReset = true
    private var isPreparing = false
    private var isCountdownPaused = false
    private var isProfileListPresented = false
    private var prepareCountdown: Int = 0
    private var prepareTimer: Timer?

    init() {
        heartRateMonitor = HeartRateMonitor()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        heartRateMonitor.delegate = self
        setupEngine()
        setupUI()
        setupActions()
        updateUI()
        impactGenerator.prepare()
        notificationGenerator.prepare()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResignActive),
            name: UIScene.willDeactivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnterForeground),
            name: UIScene.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceRemoved),
            name: NSNotification.Name("DeviceRemoved"),
            object: nil
        )
    }

    private func setupEngine() {
        let profile = ProfileManager.shared.currentProfile
        let config = WorkoutConfig(
            warmUpSeconds: profile.warmUpEnabled ? profile.warmUpSeconds : 0,
            workSeconds: profile.workSeconds,
            restSeconds: profile.restSeconds,
            rounds: profile.rounds,
            coolDownSeconds: profile.coolDownEnabled ? profile.coolDownSeconds : 0
        )
        engine = IntervalEngine(config: config)
        engine.delegate = self
    }

    private func setupActions() {
        let profileTap = UITapGestureRecognizer(target: self, action: #selector(showProfileList))
        profileLabel.isUserInteractionEnabled = true
        profileLabel.addGestureRecognizer(profileTap)

        goButton.addTarget(self, action: #selector(handleGo), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(handleSettings), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(handleReset), for: .touchUpInside)
    }

    @objc private func showProfileList() {
        // Only allow profile selection when timer is reset or finished
        guard hasReset || engine.phase == .finished else { return }

        let vc = ProfileListViewController()
        vc.onSelect = { [weak self] in
            self?.setupEngine()
            self?.updateUI()
        }
        vc.onDismiss = { [weak self] in
            self?.isProfileListPresented = false
            self?.updateProfileArrow(animated: true)
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }

        // Animate arrow rotation and track presentation state
        isProfileListPresented = true
        updateProfileArrow(animated: true)

        present(nav, animated: true)
    }

    private func updateProfileArrow(animated: Bool) {
        let profile = ProfileManager.shared.currentProfile
        let arrow = isProfileListPresented ? "▲" : "▼"
        let newText = "\(profile.name) \(arrow)"

        if animated {
            UIView.transition(with: profileLabel, duration: 0.2, options: .transitionCrossDissolve, animations: {
                self.profileLabel.text = newText
            }, completion: nil)
        } else {
            profileLabel.text = newText
        }
    }

    @objc private func handleGo() {
        if isPreparing {
            // Handle countdown pause/resume
            if isCountdownPaused {
                // Resume countdown
                isCountdownPaused = false
                resumeCountdown()
                UIApplication.shared.isIdleTimerDisabled = true
            } else {
                // Pause countdown
                isCountdownPaused = true
                pauseCountdown()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            updateGoButton()
            return
        }

        // If workout finished, reset and start countdown
        if engine.phase == .finished {
            handleReset()
            let profile = ProfileManager.shared.currentProfile
            if profile.prepareCountingSoundEnabled {
                startCountdown()
            } else {
                engine.start()
                isRunning = true
            }
            hasReset = false
            UIApplication.shared.isIdleTimerDisabled = true
            updateGoButton()
            return
        }

        if isRunning {
            engine.pause()
            isRunning = false
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            let profile = ProfileManager.shared.currentProfile
            if hasReset && profile.prepareCountingSoundEnabled && engine.phase == .warmUp && engine.remainingSeconds == (profile.warmUpEnabled ? profile.warmUpSeconds : 0) {
                startCountdown()
            } else {
                engine.start()
                isRunning = true
            }
            hasReset = false
            UIApplication.shared.isIdleTimerDisabled = true
        }
        updateGoButton()
    }

    private func startCountdown() {
        let profile = ProfileManager.shared.currentProfile
        isPreparing = true
        isCountdownPaused = false
        prepareCountdown = profile.prepareTime
        updateUI()

        prepareTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            SoundManager.shared.playCountdownBeep()
            self.prepareCountdown -= 1
            self.updateUI()

            if self.prepareCountdown == 0 {
                timer.invalidate()
                self.prepareTimer = nil
                self.isPreparing = false
                self.engine.start()
                self.isRunning = true
                self.updateUI()
                self.updateGoButton()
            }
        }
        prepareTimer?.fire()
    }

    private func pauseCountdown() {
        prepareTimer?.invalidate()
        prepareTimer = nil
        updateUI()
    }

    private func resumeCountdown() {
        prepareTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            SoundManager.shared.playCountdownBeep()
            self.prepareCountdown -= 1
            self.updateUI()

            if self.prepareCountdown == 0 {
                timer.invalidate()
                self.prepareTimer = nil
                self.isPreparing = false
                self.engine.start()
                self.isRunning = true
                self.updateUI()
                self.updateGoButton()
            }
        }
        prepareTimer?.fire()
    }

    @objc private func handleSettings() {
        let vc = SettingsViewController()
        vc.heartRateMonitor = heartRateMonitor
        vc.onSave = { [weak self] in
            self?.setupEngine()
            self?.updateUI()
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(nav, animated: true)
    }

    @objc private func handleReset() {
        // Stop countdown if in progress
        if isPreparing {
            prepareTimer?.invalidate()
            prepareTimer = nil
            isPreparing = false
            isCountdownPaused = false
            prepareCountdown = 0
        }

        engine.reset()
        isRunning = false
        hasReset = true
        updateGoButton()
        updateUI()
    }

    @objc private func handleResignActive() {
        backgroundTimestamp = Date()

        // Pause countdown if in progress
        if isPreparing && !isCountdownPaused {
            isCountdownPaused = true
            prepareTimer?.invalidate()
            prepareTimer = nil
        }

        // Pause engine if running
        if isRunning {
            engine.pause()
            isRunning = false
        }

        // Allow screen to lock when in background
        UIApplication.shared.isIdleTimerDisabled = false

        updateGoButton()
    }

    @objc private func handleEnterForeground() {
        guard let timestamp = backgroundTimestamp else { return }
        let elapsed = Int(Date().timeIntervalSince(timestamp))
        backgroundTimestamp = nil

        // Resume countdown if was in progress
        if isPreparing && isCountdownPaused {
            isCountdownPaused = false
            resumeCountdown()
            UIApplication.shared.isIdleTimerDisabled = true
            updateGoButton()
            return
        }

        // Resume engine if was running
        if !hasReset && engine.phase != .finished {
            if elapsed > 0 && engine.phase != .warmUp {
                for _ in 0..<min(elapsed, engine.remainingSeconds) {
                    engine.tick()
                }
            }
            engine.start()
            isRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            updateGoButton()
        }
    }

    private func updateGoButton() {
        if isPreparing {
            if isCountdownPaused {
                goButton.setTitle(L("Resume"), for: .normal)
            } else {
                goButton.setTitle(L("Pause"), for: .normal)
            }
        } else if isRunning {
            goButton.setTitle(L("Pause"), for: .normal)
        } else if engine.phase == .finished {
            goButton.setTitle(L("Go"), for: .normal)
        } else if hasReset {
            goButton.setTitle(L("Go"), for: .normal)
        } else {
            goButton.setTitle(L("Resume"), for: .normal)
        }
        settingsButton.isEnabled = !isRunning && (hasReset || engine.phase == .finished)
        settingsButton.alpha = settingsButton.isEnabled ? 1.0 : 0.5
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        setupTimerArea()
        setupHeader()
        setupOpView()
        setupHeartRateArea()
    }

    private func setupHeader() {
        headerView.backgroundColor = .clear
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        workLabel.text = L("Work")
        workLabel.font = .systemFont(ofSize: 20, weight: .bold)
        workLabel.textAlignment = .left
        workLabel.translatesAutoresizingMaskIntoConstraints = false

        workTimeLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        workTimeLabel.textAlignment = .left
        workTimeLabel.translatesAutoresizingMaskIntoConstraints = false

        profileLabel.font = .systemFont(ofSize: 22, weight: .bold)
        profileLabel.textAlignment = .center
        profileLabel.translatesAutoresizingMaskIntoConstraints = false

        restLabel.text = L("Rest")
        restLabel.font = .systemFont(ofSize: 20, weight: .bold)
        restLabel.textAlignment = .right
        restLabel.translatesAutoresizingMaskIntoConstraints = false

        restTimeLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        restTimeLabel.textAlignment = .right
        restTimeLabel.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(workLabel)
        headerView.addSubview(workTimeLabel)
        headerView.addSubview(profileLabel)
        headerView.addSubview(restLabel)
        headerView.addSubview(restTimeLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: timerContainer!.topAnchor, constant: 60),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            headerView.heightAnchor.constraint(equalToConstant: 60),

            workLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            workLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),

            workTimeLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            workTimeLabel.topAnchor.constraint(equalTo: workLabel.bottomAnchor, constant: 4),

            profileLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            profileLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            restLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            restLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),

            restTimeLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            restTimeLabel.topAnchor.constraint(equalTo: restLabel.bottomAnchor, constant: 4)
        ])
    }

    private func setupTimerArea() {
        let timerContainer = UIView()
        timerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerContainer)

        let timerCenterY = timerContainer.centerYAnchor

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 140, weight: .bold)
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        roundLabel.font = .systemFont(ofSize: 24, weight: .bold)
        roundLabel.textAlignment = .center
        roundLabel.adjustsFontSizeToFitWidth = true
        roundLabel.translatesAutoresizingMaskIntoConstraints = false

        timerContainer.addSubview(timeLabel)
        timerContainer.addSubview(roundLabel)

        NSLayoutConstraint.activate([
            timerContainer.topAnchor.constraint(equalTo: view.topAnchor),
            timerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            timerContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.65),

            timeLabel.centerXAnchor.constraint(equalTo: timerContainer.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: timerCenterY, constant: -20),
            timeLabel.leadingAnchor.constraint(equalTo: timerContainer.leadingAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: timerContainer.trailingAnchor, constant: -16),

            roundLabel.centerXAnchor.constraint(equalTo: timerContainer.centerXAnchor),
            roundLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 20)
        ])

        self.timerContainer = timerContainer
    }

    private var timerContainer: UIView?

    private func setupHeartRateArea() {
        heartRateContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heartRateContainer)

        heartRateLabel.text = "--"
        heartRateLabel.font = .monospacedDigitSystemFont(ofSize: 140, weight: .bold)
        heartRateLabel.textAlignment = .center
        heartRateLabel.adjustsFontSizeToFitWidth = true
        heartRateLabel.translatesAutoresizingMaskIntoConstraints = false

        connectionLabel.text = L("Disconnected")
        connectionLabel.font = .systemFont(ofSize: 16)
        connectionLabel.textColor = .systemGray
        connectionLabel.translatesAutoresizingMaskIntoConstraints = false

        addButton.setTitle("+", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .bold)
        addButton.setTitleColor(.systemYellow, for: .normal)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        connectionStackView.axis = .horizontal
        connectionStackView.alignment = .center
        connectionStackView.distribution = .equalCentering
        connectionStackView.spacing = 8
        connectionStackView.translatesAutoresizingMaskIntoConstraints = false
        connectionStackView.addArrangedSubview(connectionLabel)
        connectionStackView.addArrangedSubview(addButton)

        // Make entire stack view tappable
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleAddDevice))
        connectionStackView.isUserInteractionEnabled = true
        connectionStackView.addGestureRecognizer(tapGesture)

        heartRateContainer.addSubview(heartRateLabel)
        heartRateContainer.addSubview(connectionStackView)

        NSLayoutConstraint.activate([
            heartRateContainer.topAnchor.constraint(equalTo: timerContainer!.bottomAnchor),
            heartRateContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heartRateContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heartRateContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            heartRateLabel.centerXAnchor.constraint(equalTo: heartRateContainer.centerXAnchor),
            heartRateLabel.centerYAnchor.constraint(equalTo: heartRateContainer.centerYAnchor, constant: -20),

            connectionStackView.centerXAnchor.constraint(equalTo: heartRateContainer.centerXAnchor),
            connectionStackView.topAnchor.constraint(equalTo: heartRateLabel.bottomAnchor, constant: 16)
        ])
    }

    @objc private func handleAddDevice() {
        // Try to connect to default device first, then other saved devices, then scan
        heartRateMonitor.autoConnect()
    }

    @objc private func handleDeviceRemoved(_ notification: Notification) {
        guard let removedUUID = notification.userInfo?["uuid"] as? String else { return }

        // Check if removed device is currently connected
        if heartRateMonitor.isConnectedDevice(uuid: removedUUID) {
            // Update UI to show disconnected state
            connectionLabel.text = L("Disconnected")
            heartRateLabel.text = "--"
            addButton.isHidden = false
            connectedDeviceName = nil
        }
    }

    private func setupOpView() {
        opView.backgroundColor = .clear
        opView.translatesAutoresizingMaskIntoConstraints = false
        timerContainer!.addSubview(opView)

        // Go button - larger, bold, red background
        goButton.setTitle(L("Go"), for: .normal)
        goButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .bold)
        goButton.setTitleColor(.white, for: .normal)
        goButton.backgroundColor = .systemRed
        goButton.layer.cornerRadius = 12
        goButton.layer.borderWidth = 2
        goButton.layer.borderColor = UIColor.white.cgColor
        goButton.translatesAutoresizingMaskIntoConstraints = false

        // Settings button - red background, white text, white border
        settingsButton.setTitle(L("Settings"), for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.backgroundColor = .systemRed
        settingsButton.layer.cornerRadius = 10
        settingsButton.layer.borderWidth = 2
        settingsButton.layer.borderColor = UIColor.white.cgColor
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        // Reset button - red background, white text, white border
        resetButton.setTitle(L("Reset"), for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.backgroundColor = .systemRed
        resetButton.layer.cornerRadius = 10
        resetButton.layer.borderWidth = 2
        resetButton.layer.borderColor = UIColor.white.cgColor
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        opView.addSubview(goButton)
        opView.addSubview(settingsButton)
        opView.addSubview(resetButton)

        NSLayoutConstraint.activate([
            opView.leadingAnchor.constraint(equalTo: timerContainer!.leadingAnchor),
            opView.trailingAnchor.constraint(equalTo: timerContainer!.trailingAnchor),
            opView.bottomAnchor.constraint(equalTo: timerContainer!.bottomAnchor),
            opView.heightAnchor.constraint(equalToConstant: 120),

            goButton.centerXAnchor.constraint(equalTo: opView.centerXAnchor),
            goButton.topAnchor.constraint(equalTo: opView.topAnchor, constant: 12),
            goButton.widthAnchor.constraint(equalToConstant: 140),
            goButton.heightAnchor.constraint(equalToConstant: 56),

            settingsButton.leadingAnchor.constraint(equalTo: opView.leadingAnchor, constant: 24),
            settingsButton.centerYAnchor.constraint(equalTo: goButton.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 100),
            settingsButton.heightAnchor.constraint(equalToConstant: 48),

            resetButton.trailingAnchor.constraint(equalTo: opView.trailingAnchor, constant: -24),
            resetButton.centerYAnchor.constraint(equalTo: goButton.centerYAnchor),
            resetButton.widthAnchor.constraint(equalToConstant: 100),
            resetButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func updateUI() {
        updateProfileArrow(animated: false)
        let profile = ProfileManager.shared.currentProfile
        workTimeLabel.text = formatTime(profile.workSeconds)
        restTimeLabel.text = formatTime(profile.restSeconds)

        if isPreparing {
            timeLabel.text = "\(prepareCountdown)"
            roundLabel.text = L("Prepare")
        } else if isRunning || (!hasReset && engine.phase != .finished) {
            // Show round label only when timer is running or paused (not reset and not finished)
            timeLabel.text = formatTime(engine.remainingSeconds)
            roundLabel.text = formatRound()
        } else {
            // Initial state or after reset/finish - don't show round label
            timeLabel.text = formatTime(engine.remainingSeconds)
            roundLabel.text = ""
        }

        updateColors()
        updateGoButton()
    }

    private func updateColors() {
        let profile = ProfileManager.shared.currentProfile
        let hrColor = UIColor(hex: profile.heartRateColor) ?? .systemRed.withAlphaComponent(0.1)
        let prepareColor = UIColor(hex: profile.prepareColor) ?? .systemRed.withAlphaComponent(0.05)

        let timerColor: UIColor
        if isPreparing {
            timerColor = prepareColor
        } else if let phaseItem = engine.currentPhaseItem {
            timerColor = UIColor(hex: phaseItem.color) ?? .systemGray
        } else {
            timerColor = .systemGray
        }

        headerView.backgroundColor = timerColor
        timerContainer?.backgroundColor = timerColor
        heartRateContainer.backgroundColor = hrColor
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatRound() -> String {
        let profile = ProfileManager.shared.currentProfile
        switch engine.phase {
        case .warmUp:
            return L("Warm Up")
        case .work, .rest:
            return String(format: L("Round %d / %d"), engine.currentRound, profile.rounds)
        case .coolDown:
            return L("Cool Down")
        case .finished:
            return L("Finished")
        }
    }

    func engineDidUpdateState(_ engine: IntervalEngine) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }

    func engineDidTransitionToPhase(_ engine: IntervalEngine, phase: IntervalPhase) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateUI()
            self.impactGenerator.impactOccurred()
        }
    }

    func engineDidEndPhase(_ engine: IntervalEngine, phase: IntervalPhase) {
        // No longer needed - sounds are now handled in engineDidPlaySound
    }

    func engineDidPlaySound(_ engine: IntervalEngine, sound: String) {
        DispatchQueue.main.async {
            SoundManager.shared.playSound(sound)
        }
    }

    func engineDidSpeak(_ engine: IntervalEngine, text: String) {
        DispatchQueue.main.async {
            VoiceManager.shared.speak(text)
        }
    }

    func engineDidFinish(_ engine: IntervalEngine) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateUI()
            self.notificationGenerator.notificationOccurred(.success)
            UIApplication.shared.isIdleTimerDisabled = false
            self.isRunning = false
            self.hasReset = false
            self.updateGoButton()
        }
    }

    func heartRateMonitor(_ monitor: HeartRateMonitor, didUpdateHeartRate bpm: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heartRateLabel.text = "\(bpm)"

            UIView.animate(withDuration: 0.1) {
                self.heartRateLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            } completion: { _ in
                UIView.animate(withDuration: 0.1) {
                    self.heartRateLabel.transform = .identity
                }
            }
        }
    }

    func heartRateMonitor(_ monitor: HeartRateMonitor, didChangeState state: HeartRateMonitorState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch state {
            case .idle:
                self.connectionLabel.text = L("Disconnected")
                self.heartRateLabel.text = "--"
                self.addButton.isHidden = false
                self.isConnected = false
            case .scanning:
                self.connectionLabel.text = L("Scanning…")
                self.addButton.isHidden = true
            case .connecting:
                if let deviceName = monitor.connectedDeviceName {
                    self.connectionLabel.text = "\(L("Connecting"))… \(deviceName)"
                } else {
                    self.connectionLabel.text = L("Connecting") + "…"
                }
                self.addButton.isHidden = true
            case .connected:
                self.isConnected = true
                self.addButton.isHidden = true
                // Update connection label with device name
                if let deviceName = monitor.connectedDeviceName {
                    self.connectionLabel.text = deviceName
                    self.connectedDeviceName = deviceName
                }
            case .disconnected:
                self.connectionLabel.text = L("Disconnected")
                self.heartRateLabel.text = "--"
                self.addButton.isHidden = false
                self.isConnected = false
                self.connectedDeviceName = nil
            }
        }
    }

    func heartRateMonitor(_ monitor: HeartRateMonitor, didConnectDevice name: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectedDeviceName = name
            self.connectionLabel.text = name
        }
    }

    func heartRateMonitor(_ monitor: HeartRateMonitor, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionLabel.text = L("Error")
            self?.addButton.isHidden = false
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    func toHexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)

        let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        return String(format: "#%06x", rgb)
    }
}
