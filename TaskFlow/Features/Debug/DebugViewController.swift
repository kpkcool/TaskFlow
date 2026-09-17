//
//  DebugViewController.swift
//  TaskFlow
//
//  Lightweight developer screen for exercising offline-first behavior
//  without needing to actually turn off Wi-Fi: shows live network/sync
//  state and lets QA simulate offline, force a sync, or wipe local data.
//

import UIKit

final class DebugViewController: UIViewController {

    var onDone: (() -> Void)?

    private let repository: TaskRepository
    private var refreshTask: _Concurrency.Task<Void, Never>?
    private var syncObservationTask: _Concurrency.Task<Void, Never>?

    private let networkValueLabel = DebugViewController.valueLabel()
    private let pendingValueLabel = DebugViewController.valueLabel()
    private let lastSyncValueLabel = DebugViewController.valueLabel()
    private let simulateOfflineSwitch = UISwitch()

    init(repository: TaskRepository) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTask?.cancel()
        syncObservationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Developer"
        view.backgroundColor = .systemGroupedBackground
        // `.cancel` (not `.done`) to match the same circular "X" close
        // button style already used by TaskEditorViewController, since this
        // is an info sheet to dismiss, not a form to confirm.
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(doneTapped)
        )

        setupLayout()
        simulateOfflineSwitch.isOn = NetworkMonitor.shared.isSimulatingOffline
        simulateOfflineSwitch.addTarget(self, action: #selector(simulateOfflineToggled), for: .valueChanged)

        refresh()
        observeSyncState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    private func observeSyncState() {
        syncObservationTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            for await _ in repository.observeSyncState() {
                self.refresh()
            }
        }
    }

    private func refresh() {
        networkValueLabel.text = NetworkMonitor.shared.isConnected ? "Online" : "Offline"

        refreshTask?.cancel()
        refreshTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            let count = await repository.pendingChangeCount()
            let lastSync = await repository.lastSyncDate()
            guard !_Concurrency.Task.isCancelled else { return }
            pendingValueLabel.text = "\(count)"
            lastSyncValueLabel.text = lastSync?.shortSyncTimeString ?? "Never"
        }
    }

    private func setupLayout() {
        let networkRow = Self.row(title: "Network", accessory: networkValueLabel)
        let pendingRow = Self.row(title: "Pending Changes", accessory: pendingValueLabel)
        let lastSyncRow = Self.row(title: "Last Sync", accessory: lastSyncValueLabel)
        let simulateRow = Self.row(title: "Simulate Offline", accessory: simulateOfflineSwitch)

        let syncNowButton = Self.primaryActionButton(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath")
        syncNowButton.addTarget(self, action: #selector(syncNowTapped), for: .touchUpInside)

        let clearDataButton = Self.destructiveActionButton(title: "Clear Local Data", systemImage: "trash")
        clearDataButton.addTarget(self, action: #selector(clearDataTapped), for: .touchUpInside)

        let card = UIStackView(arrangedSubviews: [networkRow, pendingRow, lastSyncRow, simulateRow])
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12

        let stack = UIStackView(arrangedSubviews: [card, syncNowButton, clearDataButton])
        stack.axis = .vertical
        stack.spacing = 20

        // Pinning the stack to all four safe-area edges would make
        // UIStackView's .fill distribution stretch the buttons to consume
        // the leftover vertical space (their tinted backgrounds make that
        // stretch obvious, unlike a plain label). A scroll view lets the
        // stack keep its natural, compact height instead.
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.pinToSafeArea(of: self)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        contentView.addSubview(stack)
        stack.pinEdges(to: contentView, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
    }

    @objc private func doneTapped() {
        onDone?()
    }

    @objc private func simulateOfflineToggled() {
        NetworkMonitor.shared.setSimulatedOffline(simulateOfflineSwitch.isOn)
        refresh()
    }

    @objc private func syncNowTapped() {
        _Concurrency.Task { [weak self] in
            await self?.repository.syncPendingChanges()
            self?.refresh()
        }
    }

    @objc private func clearDataTapped() {
        let alert = UIAlertController(
            title: "Clear all local data?",
            message: "This removes every task from this device. It cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            _Concurrency.Task {
                try? await self.repository.clearAllLocalData()
                self.refresh()
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Row builders

    private static func valueLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }

    private static func row(title: String, accessory: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)

        let row = UIStackView(arrangedSubviews: [titleLabel, accessory])
        row.axis = .horizontal
        row.distribution = .equalSpacing
        return row
    }

    /// The main call to action on this screen — a solid, high-emphasis
    /// filled button with a leading icon.
    private static func primaryActionButton(title: String, systemImage: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 8
        config.cornerStyle = .large
        config.buttonSize = .large
        return UIButton(configuration: config)
    }

    /// A destructive but secondary action — tinted (not filled) red so it
    /// doesn't visually compete with the primary action above it.
    private static func destructiveActionButton(title: String, systemImage: String) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 8
        config.baseForegroundColor = .systemRed
        config.cornerStyle = .large
        config.buttonSize = .large
        return UIButton(configuration: config)
    }
}
