// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Picker window for selecting values (single or dual column)
class PickerViewController: NSViewController {
    private let titleText: String
    private let completion: (Int) -> Void

    // Single column
    private var singleValues: [Int] = []
    private var initialSingleIndex: Int = 0
    private var isSingleColumn: Bool = false
    private var singleColumnUnit: String? = nil

    // Dual column (minutes + seconds)
    private var minutes: [Int] = []
    private var seconds: [Int] = []
    private var selectedMinutes: Int = 0
    private var selectedSeconds: Int = 0

    private var singleTableView: NSTableView?
    private var minutesTableView: NSTableView?
    private var secondsTableView: NSTableView?
    private var contentView: NSView?

    // Single column initializer
    init(title: String, values: [Int], currentValue: Int, unit: String? = nil, completion: @escaping (Int) -> Void) {
        self.titleText = title
        self.completion = completion
        self.singleValues = values
        self.initialSingleIndex = values.firstIndex(of: currentValue) ?? 0
        self.isSingleColumn = true
        self.singleColumnUnit = unit
        super.init(nibName: nil, bundle: nil)
    }

    // Dual column initializer
    init(title: String, currentValue: Int, maxMinutes: Int, completion: @escaping (Int) -> Void) {
        self.titleText = title
        self.completion = completion
        self.isSingleColumn = false

        minutes = Array(0...maxMinutes)
        seconds = Array(0...59)
        selectedMinutes = currentValue / 60
        selectedSeconds = currentValue % 60

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let width: CGFloat = isSingleColumn ? 200 : 320
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Title
        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        if isSingleColumn {
            setupSingleColumn()
        } else {
            setupDualColumn()
        }

        // Buttons
        let cancelButton = NSButton(title: L("Cancel"), target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: L("Done"), target: self, action: #selector(doneTapped))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [cancelButton, doneButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 16
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            contentView!.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contentView!.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            contentView!.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            contentView!.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentView!.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),

            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            doneButton.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    private func setupSingleColumn() {
        if let unit = singleColumnUnit {
            // With unit label
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(container)
            contentView = container

            let unitLabel = NSTextField(labelWithString: unit)
            unitLabel.font = .systemFont(ofSize: 12)
            unitLabel.alignment = .center
            unitLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(unitLabel)

            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(scrollView)

            let tableView = NSTableView()
            tableView.dataSource = self
            tableView.delegate = self
            tableView.allowsMultipleSelection = false
            tableView.allowsEmptySelection = false
            tableView.selectionHighlightStyle = .regular

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
            column.width = 160
            tableView.addTableColumn(column)

            scrollView.documentView = tableView
            singleTableView = tableView

            NSLayoutConstraint.activate([
                unitLabel.topAnchor.constraint(equalTo: container.topAnchor),
                unitLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                unitLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

                scrollView.topAnchor.constraint(equalTo: unitLabel.bottomAnchor, constant: 4),
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                scrollView.widthAnchor.constraint(equalToConstant: 80),
                scrollView.heightAnchor.constraint(equalToConstant: 280)
            ])
        } else {
            // No unit label
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            contentView = scrollView

            let tableView = NSTableView()
            tableView.dataSource = self
            tableView.delegate = self
            tableView.allowsMultipleSelection = false
            tableView.allowsEmptySelection = false
            tableView.selectionHighlightStyle = .regular

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
            column.width = 160
            tableView.addTableColumn(column)

            scrollView.documentView = tableView
            singleTableView = tableView

            NSLayoutConstraint.activate([
                scrollView.widthAnchor.constraint(equalToConstant: 180),
                scrollView.heightAnchor.constraint(equalToConstant: 280)
            ])
        }

        // Scroll to initial selection
        DispatchQueue.main.async {
            self.singleTableView?.selectRowIndexes(IndexSet(integer: self.initialSingleIndex), byExtendingSelection: false)
            if let tableView = self.singleTableView {
                self.scrollToRow(tableView, row: self.initialSingleIndex)
            }
        }
    }

    private func setupDualColumn() {
        let containerStack = NSStackView()
        containerStack.orientation = .horizontal
        containerStack.spacing = 4
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerStack)
        contentView = containerStack

        // Minutes column
        let minContainer = NSView()
        minContainer.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(minContainer)

        let minLabel = NSTextField(labelWithString: L("min"))
        minLabel.font = .systemFont(ofSize: 12)
        minLabel.alignment = .center
        minLabel.translatesAutoresizingMaskIntoConstraints = false
        minContainer.addSubview(minLabel)

        let minScrollView = NSScrollView()
        minScrollView.hasVerticalScroller = true
        minScrollView.borderType = .bezelBorder
        minScrollView.translatesAutoresizingMaskIntoConstraints = false
        minContainer.addSubview(minScrollView)

        let minTableView = NSTableView()
        minTableView.dataSource = self
        minTableView.delegate = self
        minTableView.tag = 1 // minutes
        minTableView.allowsMultipleSelection = false
        minTableView.allowsEmptySelection = false

        let minColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("minutes"))
        minColumn.width = 60
        minTableView.addTableColumn(minColumn)

        minScrollView.documentView = minTableView
        minutesTableView = minTableView

        // Seconds column
        let secContainer = NSView()
        secContainer.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(secContainer)

        let secLabel = NSTextField(labelWithString: L("sec"))
        secLabel.font = .systemFont(ofSize: 12)
        secLabel.alignment = .center
        secLabel.translatesAutoresizingMaskIntoConstraints = false
        secContainer.addSubview(secLabel)

        let secScrollView = NSScrollView()
        secScrollView.hasVerticalScroller = true
        secScrollView.borderType = .bezelBorder
        secScrollView.translatesAutoresizingMaskIntoConstraints = false
        secContainer.addSubview(secScrollView)

        let secTableView = NSTableView()
        secTableView.dataSource = self
        secTableView.delegate = self
        secTableView.tag = 2 // seconds
        secTableView.allowsMultipleSelection = false
        secTableView.allowsEmptySelection = false

        let secColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("seconds"))
        secColumn.width = 60
        secTableView.addTableColumn(secColumn)

        secScrollView.documentView = secTableView
        secondsTableView = secTableView

        NSLayoutConstraint.activate([
            minLabel.topAnchor.constraint(equalTo: minContainer.topAnchor),
            minLabel.leadingAnchor.constraint(equalTo: minContainer.leadingAnchor),
            minLabel.trailingAnchor.constraint(equalTo: minContainer.trailingAnchor),

            minScrollView.topAnchor.constraint(equalTo: minLabel.bottomAnchor, constant: 4),
            minScrollView.leadingAnchor.constraint(equalTo: minContainer.leadingAnchor),
            minScrollView.trailingAnchor.constraint(equalTo: minContainer.trailingAnchor),
            minScrollView.bottomAnchor.constraint(equalTo: minContainer.bottomAnchor),
            minScrollView.widthAnchor.constraint(equalToConstant: 80),
            minScrollView.heightAnchor.constraint(equalToConstant: 280),

            secLabel.topAnchor.constraint(equalTo: secContainer.topAnchor),
            secLabel.leadingAnchor.constraint(equalTo: secContainer.leadingAnchor),
            secLabel.trailingAnchor.constraint(equalTo: secContainer.trailingAnchor),

            secScrollView.topAnchor.constraint(equalTo: secLabel.bottomAnchor, constant: 4),
            secScrollView.leadingAnchor.constraint(equalTo: secContainer.leadingAnchor),
            secScrollView.trailingAnchor.constraint(equalTo: secContainer.trailingAnchor),
            secScrollView.bottomAnchor.constraint(equalTo: secContainer.bottomAnchor),
            secScrollView.widthAnchor.constraint(equalToConstant: 80),
            secScrollView.heightAnchor.constraint(equalToConstant: 280)
        ])

        // Scroll to initial selections
        DispatchQueue.main.async {
            minTableView.selectRowIndexes(IndexSet(integer: self.selectedMinutes), byExtendingSelection: false)
            self.scrollToRow(minTableView, row: self.selectedMinutes)

            secTableView.selectRowIndexes(IndexSet(integer: self.selectedSeconds), byExtendingSelection: false)
            self.scrollToRow(secTableView, row: self.selectedSeconds)
        }
    }

    private func scrollToRow(_ tableView: NSTableView, row: Int) {
        guard let scrollView = tableView.enclosingScrollView else { return }
        let rowHeight: CGFloat = tableView.rowHeight
        let y = CGFloat(row) * rowHeight
        let visibleRect = NSRect(x: 0, y: y, width: scrollView.contentView.bounds.width, height: rowHeight)
        scrollView.contentView.scrollToVisible(visibleRect)
    }

    @objc private func cancelTapped() {
        view.window?.sheetParent?.endSheet(view.window!)
    }

    @objc private func doneTapped() {
        if isSingleColumn {
            if let tableView = singleTableView {
                let row = tableView.selectedRow
                if row >= 0 && row < singleValues.count {
                    completion(singleValues[row])
                }
            }
        } else {
            let totalSeconds = selectedMinutes * 60 + selectedSeconds
            completion(totalSeconds)
        }
        view.window?.sheetParent?.endSheet(view.window!)
    }
}

extension PickerViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if isSingleColumn {
            return singleValues.count
        } else {
            if tableView.tag == 1 {
                return minutes.count
            } else {
                return seconds.count
            }
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 24
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(frame: NSRect(x: 0, y: 0, width: tableView.tableColumns[0].width, height: tableView.rowHeight))
        cell.isEditable = false
        cell.isBordered = false
        cell.drawsBackground = false
        cell.alignment = .center
        cell.font = .systemFont(ofSize: 14)

        if isSingleColumn {
            if row < singleValues.count {
                cell.stringValue = "\(singleValues[row])"
            }
        } else if tableView.tag == 1 {
            // Minutes
            if row < minutes.count {
                cell.stringValue = "\(minutes[row])"
            }
        } else {
            // Seconds
            if row < seconds.count {
                cell.stringValue = String(format: "%02d", seconds[row])
            }
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }

        if tableView.tag == 1 {
            selectedMinutes = tableView.selectedRow
        } else if tableView.tag == 2 {
            selectedSeconds = tableView.selectedRow
        }
    }
}
