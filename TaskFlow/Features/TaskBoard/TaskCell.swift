//
//  TaskCell.swift
//  TaskFlow
//

import UIKit

final class TaskCell: UICollectionViewCell {

    static let reuseIdentifier = "TaskCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let syncBadge = UIImageView()
    private let updatedLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 12
        cardView.layer.cornerCurve = .continuous
        contentView.addSubview(cardView)
        cardView.pinEdges(to: contentView, insets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontForContentSizeCategory = true

        syncBadge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        syncBadge.setContentHuggingPriority(.required, for: .horizontal)
        syncBadge.widthAnchor.constraint(equalToConstant: 16).isActive = true
        syncBadge.heightAnchor.constraint(equalToConstant: 16).isActive = true

        updatedLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        updatedLabel.textColor = .tertiaryLabel

        let bottomRow = UIStackView(arrangedSubviews: [updatedLabel, UIView(), syncBadge])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, bottomRow])
        stack.axis = .vertical
        stack.spacing = 4
        cardView.addSubview(stack)
        stack.pinEdges(to: cardView, insets: UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
    }

    func configure(with task: Task) {
        titleLabel.text = task.title
        descriptionLabel.text = task.taskDescription
        descriptionLabel.isHidden = task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updatedLabel.text = "Updated \(task.updatedAt.shortSyncTimeString)"

        syncBadge.image = UIImage(systemName: task.syncStatus.symbolName)?.withRenderingMode(.alwaysTemplate)
        syncBadge.tintColor = Self.color(for: task.syncStatus)

        var accessibility = task.title
        if !task.taskDescription.isEmpty { accessibility += ". \(task.taskDescription)" }
        accessibility += ". \(Self.accessibilityText(for: task.syncStatus))"
        accessibilityLabel = accessibility
    }

    private static func color(for status: SyncStatus) -> UIColor {
        switch status {
        case .synced: return .systemGreen
        case .pendingCreate, .pendingUpdate, .pendingDelete, .failed: return .systemOrange
        }
    }

    private static func accessibilityText(for status: SyncStatus) -> String {
        switch status {
        case .synced: return "Synced"
        case .pendingCreate, .pendingUpdate, .pendingDelete: return "Sync pending"
        case .failed: return "Sync failed"
        }
    }
}
