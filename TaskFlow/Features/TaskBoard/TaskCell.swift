//
//  TaskCell.swift
//  TaskFlow
//
//  Swipe left → red delete action
//  Swipe right → blue "move status" action
//

import UIKit

final class TaskCell: UICollectionViewCell {

    static let reuseIdentifier = "TaskCell"

    /// Swipe-left: delete (shows confirmation in VC).
    var onDelete: (() -> Void)?

    /// Swipe-right: move to another status (shows action sheet in VC).
    var onMoveStatus: (() -> Void)?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let syncBadge = UIImageView()
    private let updatedLabel = UILabel()

    // Swipe backgrounds
    private let deleteBackground = UIView()
    private let deleteIconView = UIImageView()
    private let moveBackground = UIView()
    private let moveIconView = UIImageView()

    private var cardLeadingConstraint: NSLayoutConstraint!
    private var panGesture: UIPanGestureRecognizer!

    private let actionThreshold: CGFloat = 80

    /// Which direction the current swipe is going — locked on first move.
    private enum SwipeDirection {
        case none, left, right
    }

    private var swipeDirection: SwipeDirection = .none

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupSwipeGesture()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDelete = nil
        onMoveStatus = nil
        resetSwipe(animated: false)
    }

    // MARK: - Layout

    private func setupViews() {
        // — Delete background (trailing, red) —
        deleteBackground.backgroundColor = .systemRed
        deleteBackground.layer.cornerRadius = 12
        deleteBackground.layer.cornerCurve = .continuous
        deleteBackground.clipsToBounds = true
        contentView.addSubview(deleteBackground)
        deleteBackground.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            deleteBackground.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 4
            ),
            deleteBackground.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -4
            ),
            deleteBackground.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -4
            ),
            deleteBackground.widthAnchor.constraint(equalToConstant: 80)
        ])

        deleteIconView.image = UIImage(systemName: "trash.fill")
        deleteIconView.tintColor = .white
        deleteIconView.contentMode = .scaleAspectFit
        deleteBackground.addSubview(deleteIconView)
        deleteIconView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            deleteIconView.centerXAnchor.constraint(
                equalTo: deleteBackground.centerXAnchor
            ),
            deleteIconView.centerYAnchor.constraint(
                equalTo: deleteBackground.centerYAnchor
            ),
            deleteIconView.widthAnchor.constraint(equalToConstant: 24),
            deleteIconView.heightAnchor.constraint(equalToConstant: 24)
        ])

        deleteBackground.alpha = 0

        // — Move background (leading, blue) —
        moveBackground.backgroundColor = .systemBlue
        moveBackground.layer.cornerRadius = 12
        moveBackground.layer.cornerCurve = .continuous
        moveBackground.clipsToBounds = true
        contentView.addSubview(moveBackground)
        moveBackground.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            moveBackground.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 4
            ),
            moveBackground.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -4
            ),
            moveBackground.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 4
            ),
            moveBackground.widthAnchor.constraint(equalToConstant: 80)
        ])

        moveIconView.image = UIImage(
            systemName: "arrow.left.arrow.right"
        )
        moveIconView.tintColor = .white
        moveIconView.contentMode = .scaleAspectFit
        moveBackground.addSubview(moveIconView)
        moveIconView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            moveIconView.centerXAnchor.constraint(
                equalTo: moveBackground.centerXAnchor
            ),
            moveIconView.centerYAnchor.constraint(
                equalTo: moveBackground.centerYAnchor
            ),
            moveIconView.widthAnchor.constraint(equalToConstant: 24),
            moveIconView.heightAnchor.constraint(equalToConstant: 24)
        ])

        moveBackground.alpha = 0

        // — Card (slides over both backgrounds) —
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 12
        cardView.layer.cornerCurve = .continuous
        contentView.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false

        cardLeadingConstraint = cardView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: 4
        )

        NSLayoutConstraint.activate([
            cardLeadingConstraint,
            cardView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 4
            ),
            cardView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -4
            ),
            cardView.widthAnchor.constraint(
                equalTo: contentView.widthAnchor,
                constant: -8
            )
        ])

        titleLabel.font = UIFont.preferredFont(
            forTextStyle: .headline
        )
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.font = UIFont.preferredFont(
            forTextStyle: .footnote
        )
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontForContentSizeCategory = true

        syncBadge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold
        )
        syncBadge.setContentHuggingPriority(
            .required,
            for: .horizontal
        )
        syncBadge.widthAnchor.constraint(
            equalToConstant: 16
        ).isActive = true
        syncBadge.heightAnchor.constraint(
            equalToConstant: 16
        ).isActive = true

        updatedLabel.font = UIFont.preferredFont(
            forTextStyle: .caption2
        )
        updatedLabel.textColor = .tertiaryLabel

        let bottomRow = UIStackView(
            arrangedSubviews: [
                updatedLabel,
                UIView(),
                syncBadge
            ]
        )
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center

        let stack = UIStackView(
            arrangedSubviews: [
                titleLabel,
                descriptionLabel,
                bottomRow
            ]
        )
        stack.axis = .vertical
        stack.spacing = 4

        cardView.addSubview(stack)
        stack.pinEdges(
            to: cardView,
            insets: UIEdgeInsets(
                top: 10,
                left: 12,
                bottom: 10,
                right: 12
            )
        )
    }

    // MARK: - Swipe gesture

    private func setupSwipeGesture() {
        panGesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan)
        )
        panGesture.delegate = self
        contentView.addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(
        _ gesture: UIPanGestureRecognizer
    ) {
        let translation = gesture.translation(in: contentView)

        switch gesture.state {
        case .began:
            swipeDirection = .none

        case .changed:
            // Lock direction on first significant move
            if swipeDirection == .none {
                if translation.x < -10 {
                    swipeDirection = .left
                } else if translation.x > 10 {
                    swipeDirection = .right
                } else {
                    return
                }
            }

            switch swipeDirection {
            case .left:
                let offset = min(
                    0,
                    max(
                        translation.x,
                        -actionThreshold - 20
                    )
                )

                cardLeadingConstraint.constant = 4 + offset

                let progress = min(
                    1,
                    abs(offset) / actionThreshold
                )

                deleteBackground.alpha = progress
                moveBackground.alpha = 0

            case .right:
                let offset = max(
                    0,
                    min(
                        translation.x,
                        actionThreshold + 20
                    )
                )

                cardLeadingConstraint.constant = 4 + offset

                let progress = min(
                    1,
                    offset / actionThreshold
                )

                moveBackground.alpha = progress
                deleteBackground.alpha = 0

            case .none:
                break
            }

        case .ended, .cancelled:
            let velocity = gesture.velocity(
                in: contentView
            ).x

            let offset = cardLeadingConstraint.constant - 4

            switch swipeDirection {
            case .left:
                if offset <= -actionThreshold || velocity < -500 {
                    // Hold open at threshold, fire delete callback
                    UIView.animate(
                        withDuration: 0.2,
                        delay: 0,
                        options: .curveEaseOut
                    ) {
                        self.cardLeadingConstraint.constant =
                            4 - self.actionThreshold
                        self.deleteBackground.alpha = 1
                        self.contentView.layoutIfNeeded()
                    } completion: { _ in
                        self.onDelete?()
                    }
                } else {
                    resetSwipe(animated: true)
                }

            case .right:
                if offset >= actionThreshold || velocity > 500 {
                    // Hold open at threshold, fire move callback
                    UIView.animate(
                        withDuration: 0.2,
                        delay: 0,
                        options: .curveEaseOut
                    ) {
                        self.cardLeadingConstraint.constant =
                            4 + self.actionThreshold
                        self.moveBackground.alpha = 1
                        self.contentView.layoutIfNeeded()
                    } completion: { _ in
                        self.onMoveStatus?()
                    }
                } else {
                    resetSwipe(animated: true)
                }

            case .none:
                resetSwipe(animated: true)
            }

            swipeDirection = .none

        default:
            break
        }
    }

    /// Public — VC calls this when the user dismisses the action sheet / alert.
    func resetSwipe(animated: Bool = true) {
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: .curveEaseOut
            ) {
                self.cardLeadingConstraint.constant = 4
                self.deleteBackground.alpha = 0
                self.moveBackground.alpha = 0
                self.contentView.layoutIfNeeded()
            }
        } else {
            cardLeadingConstraint.constant = 4
            deleteBackground.alpha = 0
            moveBackground.alpha = 0
        }

        swipeDirection = .none
    }

    // MARK: - Configuration

    func configure(with task: Task) {
        titleLabel.text = task.title
        descriptionLabel.text = task.taskDescription

        descriptionLabel.isHidden =
            task.taskDescription
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty

        updatedLabel.text =
            "Updated \(task.updatedAt.shortSyncTimeString)"

        syncBadge.image = UIImage(
            systemName: task.syncStatus.symbolName
        )?.withRenderingMode(.alwaysTemplate)

        syncBadge.tintColor = Self.color(
            for: task.syncStatus
        )

        var accessibility = task.title

        if !task.taskDescription.isEmpty {
            accessibility += ". \(task.taskDescription)"
        }

        accessibility +=
            ". \(Self.accessibilityText(for: task.syncStatus))"

        accessibilityLabel = accessibility
    }

    private static func color(
        for status: SyncStatus
    ) -> UIColor {
        switch status {
        case .synced:
            return .systemGreen

        case .pendingCreate,
             .pendingUpdate,
             .pendingDelete,
             .failed:
            return .systemOrange
        }
    }

    private static func accessibilityText(
        for status: SyncStatus
    ) -> String {
        switch status {
        case .synced:
            return "Synced"

        case .pendingCreate,
             .pendingUpdate,
             .pendingDelete:
            return "Sync pending"

        case .failed:
            return "Sync failed"
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TaskCell: UIGestureRecognizerDelegate {

    // Only begin if primarily horizontal — let vertical scrolls pass through.
    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(
                gestureRecognizer
            )
        }

        let velocity = pan.velocity(in: self)

        return abs(velocity.x) > abs(velocity.y)
    }
}
