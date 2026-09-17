//
//  TaskSectionHeader.swift
//  TaskFlow
//

import UIKit

final class TaskSectionHeader: UICollectionReusableView {

    static let reuseIdentifier = "TaskSectionHeader"
    static let elementKind = "TaskSectionHeader"

    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3).withTraits(.traitBold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        // No pill/background — the count reads as part of the title, in
        // the same color, just a lighter weight.
        countLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        countLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel, UIView()])
        stack.axis = .horizontal
        stack.spacing = 6
        // `.firstBaseline` lines up the two labels' text baselines properly
        // even though they're different fonts/sizes — `.center` was
        // centering their full frames instead, which reads as misaligned
        // when the fonts don't share the same line height.
        stack.alignment = .firstBaseline
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 8, left: 16, bottom: 4, right: 16))
    }

    func configure(status: TaskStatus, count: Int) {
        let color = Self.color(for: status)
        titleLabel.text = status.displayName
        titleLabel.textColor = color
        countLabel.text = "\(count)"
        countLabel.textColor = color.withAlphaComponent(0.6)
    }

    private static func color(for status: TaskStatus) -> UIColor {
        switch status {
        case .todo: return .systemBlue
        case .inProgress: return .systemOrange
        case .done: return .systemGreen
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
