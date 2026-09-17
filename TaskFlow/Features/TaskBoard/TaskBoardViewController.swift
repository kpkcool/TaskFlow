//
//  TaskBoardViewController.swift
//  TaskFlow
//
//  Three stacked sections (To Do / In Progress / Done) in a single
//  UICollectionViewCompositionalLayout list. Drag-and-drop works both for
//  reordering within a section and for moving a task into a different
//  section (UIKit's drop coordinator reports the destination section
//  directly); a long-press context menu offers the same "Move to..." as a
//  discoverable, non-gestural alternative.
//

import Combine
import UIKit

final class TaskBoardViewController: UIViewController {

    var onAddTask: (() -> Void)?
    var onSelectTask: ((Task) -> Void)?
    var onOpenDebug: (() -> Void)?

    private let viewModel: TaskBoardViewModel
    private var cancellables = Set<AnyCancellable>()
    private lazy var dataSource = makeDataSource()
    /// True while a drag session is active. Snapshot updates are fully
    /// deferred (not just un-animated) until the drag ends — even an
    /// un-animated `apply()` tears down and rebuilds the dragged cell,
    /// causing it to flash/disappear for a frame.
    private var isDragging = false
    /// Snapshot that arrived while `isDragging` was true. Applied once
    /// the drag session ends so the board catches up without any flicker.
    private var pendingDragSections: [TaskSection]?

    private let refreshControl = UIRefreshControl()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        collectionView.backgroundColor = .systemGroupedBackground
        // Without this, a UIScrollView whose content doesn't fill its
        // bounds (e.g. the empty-board state) won't scroll/bounce at all —
        // and pull-to-refresh is implemented as an overscroll gesture, so
        // it silently never triggers. This is what "no items" was blocking.
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.refreshControl = refreshControl
        collectionView.register(TaskCell.self, forCellWithReuseIdentifier: TaskCell.reuseIdentifier)
        collectionView.register(
            TaskSectionHeader.self,
            forSupplementaryViewOfKind: TaskSectionHeader.elementKind,
            withReuseIdentifier: TaskSectionHeader.reuseIdentifier
        )
        return collectionView
    }()

    private let bannerContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        return view
    }()

    private let bannerLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No tasks yet.\nTap + to add your first task."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }()

    private lazy var addButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "plus")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemBlue
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Add Task"
        button.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        return button
    }()

    /// Small icon-only indicator (tap = retry sync) instead of a text pill —
    /// a `UIBarButtonItem` with a title renders as a full-width capsule in
    /// recent iOS versions, which is far too loud for a status glyph.
    /// Plain `UIButton(type: .system)` + `tintColor` (not the Configuration
    /// API) so the SF Symbol reliably tints as a simple template image.
    private lazy var syncStatusButton: UIButton = {
        let button = UIButton(type: .system)
        button.imageView?.contentMode = .scaleAspectFit
        // Different SF Symbols ("checkmark.circle.fill" vs "wifi.slash",
        // etc.) have different natural glyph sizes at the same font size —
        // without pinning an explicit point size they visibly vary. This
        // keeps every state the same visual weight, matching the gear icon.
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold),
            forImageIn: .normal
        )
        button.addTarget(self, action: #selector(syncStatusTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])
        return button
    }()

    private lazy var syncStatusItem = UIBarButtonItem(customView: syncStatusButton)

    init(viewModel: TaskBoardViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let viewModel = viewModel
        _Concurrency.Task { @MainActor in
            viewModel.stop()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Task Board"
        view.backgroundColor = .systemGroupedBackground

        setupNavigationBar()
        setupLayout()
        bindViewModel()

        refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        viewModel.start()
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = syncStatusItem
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(debugTapped)
        )
    }

    private func setupLayout() {
        bannerContainer.addSubview(bannerLabel)
        bannerLabel.pinEdges(to: bannerContainer, insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))

        let stack = UIStackView(arrangedSubviews: [bannerContainer, collectionView])
        stack.axis = .vertical
        view.addSubview(stack)
        stack.pinToSafeArea(of: self)

        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(addButton)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56),
            addButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.$sections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sections in
                self?.applySnapshot(for: sections)
            }
            .store(in: &cancellables)

        viewModel.$syncState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.render(syncState: state)
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.presentError(message)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(for sections: [TaskSection]) {
        // While a drag is active, applying ANY snapshot (even unanimated)
        // tears down the dragged cell and rebuilds it — visible as a
        // flash/disappear. Queue it and apply once the drag ends.
        if isDragging {
            pendingDragSections = sections
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TaskStatus, Task>()
        snapshot.appendSections(sections.map(\.status))
        for section in sections {
            snapshot.appendItems(section.tasks, toSection: section.status)
        }
        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            self?.refreshVisibleSectionHeaders(with: sections)
        }
        refreshControl.endRefreshing()
        emptyStateLabel.isHidden = !sections.allSatisfy { $0.tasks.isEmpty }
    }

    /// Flushes any snapshot that was deferred during a drag session.
    private func flushPendingSnapshot() {
        guard let sections = pendingDragSections else { return }
        pendingDragSections = nil
        applySnapshot(for: sections)
    }

    private func refreshVisibleSectionHeaders(with sections: [TaskSection]) {
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: TaskSectionHeader.elementKind) {
            guard sections.indices.contains(indexPath.section),
                  let header = collectionView.supplementaryView(
                    forElementKind: TaskSectionHeader.elementKind,
                    at: indexPath
                  ) as? TaskSectionHeader
            else { continue }
            let section = sections[indexPath.section]
            header.configure(status: section.status, count: section.tasks.count)
        }
    }

    private func render(syncState: SyncState) {
        if let message = syncState.bannerMessage {
            bannerLabel.text = message
            bannerContainer.backgroundColor = .systemOrange
            bannerContainer.isHidden = false
        } else {
            bannerContainer.isHidden = true
        }

        let icon = Self.icon(for: syncState)
        let symbolImage = UIImage(systemName: icon.systemName)?.withRenderingMode(.alwaysTemplate)
        syncStatusButton.setImage(symbolImage, for: .normal)
        syncStatusButton.tintColor = icon.tint
        syncStatusButton.accessibilityLabel = icon.accessibilityLabel

        if case .syncing = syncState {
            startSpinningSyncIcon()
        } else {
            stopSpinningSyncIcon()
        }
    }

    private func startSpinningSyncIcon() {
        guard syncStatusButton.imageView?.layer.animation(forKey: "spin") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -Double.pi * 2
        animation.duration = 1.1
        animation.repeatCount = .infinity
        syncStatusButton.imageView?.layer.add(animation, forKey: "spin")
    }

    private func stopSpinningSyncIcon() {
        syncStatusButton.imageView?.layer.removeAnimation(forKey: "spin")
    }

    private static func icon(for state: SyncState) -> (systemName: String, tint: UIColor, accessibilityLabel: String) {
        switch state {
        case .idle:
            return ("checkmark.circle", .tertiaryLabel, "Sync idle")
        case .offline:
            return ("wifi.slash", .systemOrange, "Offline. Tap to retry sync")
        case .syncing(let count):
            let label = count > 0 ? "Syncing \(count) change\(count == 1 ? "" : "s")" : "Syncing"
            return ("arrow.triangle.2.circlepath", .systemBlue, label)
        case .synced:
            return ("checkmark.circle.fill", .systemGreen, "All changes synced")
        case .failed:
            return ("exclamationmark.triangle.fill", .systemOrange, "Sync failed. Tap to retry")
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Something went wrong", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.viewModel.errorMessage = nil
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAddTask?()
    }

    @objc private func debugTapped() {
        onOpenDebug?()
    }

    @objc private func syncStatusTapped() {
        viewModel.retrySync()
    }

    @objc private func pulledToRefresh() {
        _Concurrency.Task { [weak self] in
            await self?.viewModel.refreshAndWait()
            self?.refreshControl.endRefreshing()
        }
    }

    private func confirmDelete(_ task: Task) {
        let alert = UIAlertController(
            title: "Delete \"\(task.title)\"?",
            message: "This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteTask(task)
        })
        present(alert, animated: true)
    }

    // MARK: - Layout

    private static func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(84))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(84))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 20, trailing: 12)
        section.interGroupSpacing = 8

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(36))
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: TaskSectionHeader.elementKind,
            alignment: .top
        )
        header.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [header]

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<TaskStatus, Task> {
        let dataSource = UICollectionViewDiffableDataSource<TaskStatus, Task>(
            collectionView: collectionView
        ) { collectionView, indexPath, task in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TaskCell.reuseIdentifier,
                for: indexPath
            ) as! TaskCell
            cell.configure(with: task)
            return cell
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self, kind == TaskSectionHeader.elementKind else { return nil }
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: TaskSectionHeader.reuseIdentifier,
                for: indexPath
            ) as! TaskSectionHeader
            guard self.viewModel.sections.indices.contains(indexPath.section) else { return header }
            let section = self.viewModel.sections[indexPath.section]
            header.configure(status: section.status, count: section.tasks.count)
            return header
        }

        return dataSource
    }
}

// MARK: - UICollectionViewDelegate

extension TaskBoardViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let task = viewModel.task(at: indexPath) else { return }
        onSelectTask?(task)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let task = viewModel.task(at: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                self.onSelectTask?(task)
            }

            let moveActions = TaskStatus.allCases
                .filter { $0 != task.status }
                .map { status in
                    UIAction(title: "Move to \(status.displayName)") { _ in
                        self.viewModel.moveTask(task, to: status, targetIndex: nil)
                    }
                }
            let moveMenu = UIMenu(
                title: "Move to...",
                image: UIImage(systemName: "arrow.left.arrow.right"),
                children: moveActions
            )

            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.confirmDelete(task)
            }

            return UIMenu(children: [edit, moveMenu, delete])
        }
    }
}

// MARK: - Drag & Drop

extension TaskBoardViewController: UICollectionViewDragDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let task = viewModel.task(at: indexPath) else { return [] }
        let itemProvider = NSItemProvider(object: task.id.uuidString as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = task
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        isDragging = true
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        isDragging = false
        flushPendingSnapshot()
    }
}

extension TaskBoardViewController: UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil
    }

    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let dragItem = coordinator.items.first,
              let task = dragItem.dragItem.localObject as? Task else { return }

        let destinationIndexPath: IndexPath
        if let requested = coordinator.destinationIndexPath,
           viewModel.sections.indices.contains(requested.section) {
            destinationIndexPath = requested
        } else {
            // UIKit gives us `nil` when the user drops over an empty section
            // (no cells = no candidate indexPath). Hit-test against the
            // section header frames instead so "To Do → empty In Progress"
            // actually lands in the right section instead of silently
            // falling back to section 0.
            let location = coordinator.session.location(in: collectionView)
            let section = sectionIndex(forDropPoint: location) ?? 0
            let count = viewModel.sections.indices.contains(section) ? viewModel.sections[section].tasks.count : 0
            destinationIndexPath = IndexPath(item: count, section: section)
        }

        let destinationStatus = viewModel.sections[destinationIndexPath.section].status
        viewModel.moveTask(task, to: destinationStatus, targetIndex: destinationIndexPath.item)

        // Tell the drop coordinator where the item landed — UIKit uses
        // this for its drop animation.
        coordinator.drop(dragItem.dragItem, toItemAt: destinationIndexPath)

        // Give UIKit's drop animation ~0.2s to settle before we flush
        // the deferred snapshot. This keeps the cell visible throughout
        // the entire drag-lift → move → drop arc with zero flicker.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isDragging = false
            self?.flushPendingSnapshot()
        }
    }

    /// Finds which section the drop point is in by checking each section's
    /// vertical range (header top → last item bottom, or next header top).
    /// Works even when the section is empty (no items, just a header).
    private func sectionIndex(forDropPoint point: CGPoint) -> Int? {
        let sectionCount = viewModel.sections.count
        guard sectionCount > 0 else { return nil }

        // Collect each section's header top-Y in layout coordinates.
        var sectionTops: [(section: Int, topY: CGFloat)] = []
        for section in 0..<sectionCount {
            let headerIndexPath = IndexPath(item: 0, section: section)
            if let attrs = collectionView.layoutAttributesForSupplementaryElement(
                ofKind: TaskSectionHeader.elementKind,
                at: headerIndexPath
            ) {
                sectionTops.append((section, attrs.frame.minY))
            }
        }

        // Walk from bottom to top: the first section whose header is above
        // the drop point is the one we're in.
        for entry in sectionTops.reversed() {
            if point.y >= entry.topY {
                return entry.section
            }
        }
        return sectionTops.first?.section
    }
}
