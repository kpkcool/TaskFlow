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
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
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
            EmptySectionPlaceholder.self,
            forSupplementaryViewOfKind: EmptySectionPlaceholder.elementKind,
            withReuseIdentifier: EmptySectionPlaceholder.reuseIdentifier
        )
        collectionView.register(
            TaskSectionHeader.self,
            forSupplementaryViewOfKind: TaskSectionHeader.elementKind,
            withReuseIdentifier: TaskSectionHeader.reuseIdentifier
        )
        return collectionView
    }()

    /// Floating toast that overlays the collection view - never pushes
    /// it down or triggers a relayout. Auto-hides after 3 seconds.
    private let toastLabel: UIPaddedLabel = {
        let label = UIPaddedLabel()

        label.font = .preferredFont(
            forTextStyle: .footnote,
            compatibleWith: nil
        )
        label.textColor = .white
        label.numberOfLines = 1
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.backgroundColor = .systemOrange
        label.layer.cornerRadius = 18
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.alpha = 0
        label.isUserInteractionEnabled = false

        return label
    }()

    private var toastHideWork: DispatchWorkItem?

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No tasks yet.\nTap + to add your first task."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .quaternaryLabel
        label.font = .preferredFont(forTextStyle: .subheadline)
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
        Task { @MainActor in
            viewModel.stop()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Task Flow"
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
        view.addSubview(collectionView)
        collectionView.pinToSafeArea(of: self)

        // Add button first - toast references it.
        view.addSubview(addButton)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56),
            addButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -20
            ),
            addButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -20
            )
        ])

        // Toast floats at bottom-right, just above the + button.
        view.addSubview(toastLabel)
        toastLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toastLabel.bottomAnchor.constraint(
                equalTo: addButton.topAnchor,
                constant: -12
            ),
            toastLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            toastLabel.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 36
            )
        ])

        // Position the empty-state label just above the + button
        // so it doesn't overlap with the dashed section placeholders.
        view.addSubview(emptyStateLabel)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            emptyStateLabel.bottomAnchor.constraint(
                equalTo: addButton.topAnchor,
                constant: -16
            ),
            emptyStateLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 32
            ),
            emptyStateLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -32
            )
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
        if isDragging {
            pendingDragSections = sections
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TaskStatus, Task>()
        snapshot.appendSections(sections.map(\.status))
        for section in sections {
            snapshot.appendItems(section.tasks, toSection: section.status)
        }
        // No animation — keeps reordering instant and prevents any jitter.
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleSectionHeaders(with: sections)
        }
        // Invalidate layout so the per-section provider re-evaluates whether
        // each section needs the empty placeholder footer or not.
        collectionView.collectionViewLayout.invalidateLayout()
        refreshControl.endRefreshing()
        emptyStateLabel.isHidden = !sections.allSatisfy { $0.tasks.isEmpty }
    }

    /// Flushes any snapshot that was deferred during a drag session.
    /// Applied WITHOUT animation so the post-drop update is instant — no
    /// jittery layout animation fighting with the drag settling.
    private func flushPendingSnapshot() {
        guard let sections = pendingDragSections else { return }
        pendingDragSections = nil

        var snapshot = NSDiffableDataSourceSnapshot<TaskStatus, Task>()
        snapshot.appendSections(sections.map(\.status))
        for section in sections {
            snapshot.appendItems(section.tasks, toSection: section.status)
        }
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleSectionHeaders(with: sections)
        }
        emptyStateLabel.isHidden = !sections.allSatisfy { $0.tasks.isEmpty }
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
        // Update placeholder visibility to match current task counts.
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: EmptySectionPlaceholder.elementKind) {
            guard let placeholder = collectionView.supplementaryView(
                forElementKind: EmptySectionPlaceholder.elementKind,
                at: indexPath
            ) as? EmptySectionPlaceholder else { continue }
            let isEmpty = sections.indices.contains(indexPath.section)
                ? sections[indexPath.section].tasks.isEmpty
                : true
            placeholder.configure(isEmpty: isEmpty)
        }
    }

    private func render(syncState: SyncState) {
        // Update the nav-bar sync icon
        let icon = Self.icon(for: syncState)

        let symbolImage = UIImage(
            systemName: icon.systemName
        )?.withRenderingMode(.alwaysTemplate)

        syncStatusButton.setImage(
            symbolImage,
            for: .normal
        )

        syncStatusButton.tintColor = icon.tint
        syncStatusButton.accessibilityLabel = icon.accessibilityLabel

        if case .syncing = syncState {
            startSpinningSyncIcon()
        } else {
            stopSpinningSyncIcon()
        }

        // Show a brief toast for transient states, dismiss for settled ones.
        if let message = syncState.bannerMessage {
            showToast(message)
        } else {
            hideToast()
        }
    }
    
    private func showToast(_ message: String) {
        toastHideWork?.cancel()

        toastLabel.text = message

        UIView.animate(withDuration: 0.25) {
            self.toastLabel.alpha = 1
        }

        // Auto-hide after 3 seconds unless a new message replaces it.
        let work = DispatchWorkItem { [weak self] in
            self?.hideToast()
        }

        toastHideWork = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 3,
            execute: work
        )
    }
    
    private func hideToast() {
        toastHideWork?.cancel()
        toastHideWork = nil

        UIView.animate(withDuration: 0.25) {
            self.toastLabel.alpha = 0
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
        Task { [weak self] in
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

    /// Swipe-to-delete variant: shows confirmation, then either deletes or
    /// snaps the cell's card back to its resting position on cancel.
    private func confirmSwipeDelete(_ task: Task, cell: TaskCell?) {
        let alert = UIAlertController(
            title: "Delete \"\(task.title)\"?",
            message: "This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            cell?.resetSwipe()
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteTask(task)
        })
        present(alert, animated: true)
    }

    /// Swipe-right: shows a custom bottom sheet with color-coded status buttons.
    private func showMoveStatusSheet(_ task: Task, cell: TaskCell?) {
        let sheet = MoveStatusSheetController(task: task)
        sheet.onSelect = { [weak self] status in
            self?.viewModel.moveTask(task, to: status, targetIndex: nil)
            cell?.resetSwipe()
        }
        sheet.onCancel = {
            cell?.resetSwipe()
        }
        present(sheet, animated: true)
    }

    // MARK: - Layout

    /// Per-section layout: empty sections get a 60pt placeholder footer;
    /// non-empty sections get no footer at all (zero wasted space).
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(84))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(84))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12)
            section.interGroupSpacing = 8

            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(36))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: TaskSectionHeader.elementKind,
                alignment: .top
            )
            header.pinToVisibleBounds = true

            let isEmpty = self?.viewModel.sections.indices.contains(sectionIndex) == true
                ? self!.viewModel.sections[sectionIndex].tasks.isEmpty
                : true

            if isEmpty {
                let footerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(60))
                let footer = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: footerSize,
                    elementKind: EmptySectionPlaceholder.elementKind,
                    alignment: .bottom
                )
                section.boundarySupplementaryItems = [header, footer]
            } else {
                section.boundarySupplementaryItems = [header]
            }

            return section
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<TaskStatus, Task> {
        let dataSource = UICollectionViewDiffableDataSource<TaskStatus, Task>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, task in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TaskCell.reuseIdentifier,
                for: indexPath
            ) as! TaskCell
            cell.configure(with: task)
            cell.onDelete = { [weak self, weak cell] in
                self?.confirmSwipeDelete(task, cell: cell)
            }
            cell.onMoveStatus = { [weak self, weak cell] in
                self?.showMoveStatusSheet(task, cell: cell)
            }
            return cell
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }

            if kind == TaskSectionHeader.elementKind {
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

            if kind == EmptySectionPlaceholder.elementKind {
                let placeholder = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: EmptySectionPlaceholder.reuseIdentifier,
                    for: indexPath
                ) as! EmptySectionPlaceholder
                let isEmpty = self.viewModel.sections.indices.contains(indexPath.section)
                    ? self.viewModel.sections[indexPath.section].tasks.isEmpty
                    : true
                placeholder.configure(isEmpty: isEmpty)
                return placeholder
            }

            return nil
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
        UICollectionViewDropProposal(operation: .move, intent: .unspecified)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let dragItem = coordinator.items.first,
              let task = dragItem.dragItem.localObject as? Task else { return }

        let location = coordinator.session.location(in: collectionView)
        let section = sectionForDropPoint(location)
        let destinationStatus = viewModel.sections[section].status

        // Calculate the insertion index within the target section by
        // comparing the drop Y against visible cell midpoints.
        let targetIndex = insertionIndex(forDropPoint: location, inSection: section, excludingTaskID: task.id)

        viewModel.moveTask(task, to: destinationStatus, targetIndex: targetIndex)

        isDragging = false
        flushPendingSnapshot()
    }

    /// Simple, reliable section detection: divide the collection view into
    /// vertical bands based on the fraction of total content each section
    /// occupies. For 3 sections this just splits the visible area into
    /// thirds (roughly), biased by where the headers actually are.
    private func sectionForDropPoint(_ point: CGPoint) -> Int {
        let sectionCount = viewModel.sections.count
        guard sectionCount > 0 else { return 0 }

        // Collect the Y-origin of each section's header.
        var tops: [(section: Int, y: CGFloat)] = []
        for section in 0..<sectionCount {
            // Try visible subview first (most accurate).
            let ip = IndexPath(item: 0, section: section)
            if let header = collectionView.supplementaryView(forElementKind: TaskSectionHeader.elementKind, at: ip) {
                tops.append((section, header.frame.minY))
            } else if let attrs = collectionView.layoutAttributesForSupplementaryElement(
                ofKind: TaskSectionHeader.elementKind, at: ip
            ) {
                tops.append((section, attrs.frame.minY))
            }
        }

        guard !tops.isEmpty else { return 0 }
        tops.sort { $0.y < $1.y }

        // Walk bottom-to-top: first header that's above the drop point.
        for entry in tops.reversed() {
            if point.y >= entry.y {
                return entry.section
            }
        }
        return tops.first?.section ?? 0
    }

    /// Determines where within a section the task should be inserted by
    /// comparing the drop Y against the midpoints of existing cells.
    private func insertionIndex(forDropPoint point: CGPoint, inSection section: Int, excludingTaskID: UUID) -> Int {
        let tasks = viewModel.sections[section].tasks.filter { $0.id != excludingTaskID }
        guard !tasks.isEmpty else { return 0 }

        // Walk the visible cells in this section and find where the drop
        // point sits relative to their vertical midpoints.
        for (index, task) in tasks.enumerated() {
            // Find the cell for this task via its indexPath in the snapshot.
            let snapshot = dataSource.snapshot()
            guard let itemIndex = snapshot.indexOfItem(task) else { continue }
            let sectionItems = snapshot.itemIdentifiers(inSection: viewModel.sections[section].status)
            guard let localIndex = sectionItems.firstIndex(of: task) else { continue }
            let indexPath = IndexPath(item: localIndex, section: section)

            if let attrs = collectionView.layoutAttributesForItem(at: indexPath) {
                if point.y < attrs.frame.midY {
                    return index
                }
            }
        }
        // Below all cells — append at end.
        return tasks.count
    }
}

// MARK: - UIPaddedLabel

/// A UILabel with built-in content padding so the toast pill has insets
/// without needing a wrapper view.
private final class UIPaddedLabel: UILabel {

    var contentInsets = UIEdgeInsets(
        top: 8,
        left: 16,
        bottom: 8,
        right: 16
    )

    override func drawText(in rect: CGRect) {
        super.drawText(
            in: rect.inset(by: contentInsets)
        )
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize

        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}
