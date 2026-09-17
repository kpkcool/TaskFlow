//  EmptySectionPlaceholder.swift
//  TaskFlow
//
//  A dashed-border placeholder that appears in empty board sections,
//  giving users a visible drop target (like Jira's empty columns).
//  Uses quaternaryLabel for a very light appearance that still adapts
//  to dark mode automatically.
//

import UIKit

final class EmptySectionPlaceholder: UICollectionReusableView {

    static let reuseIdentifier = "EmptySectionPlaceholder"
    static let elementKind = "EmptySectionPlaceholder"

    private let dashedView = UIView()
    private let label = UILabel()
    private let dashedLayer = CAShapeLayer()

    /// The semantic color for the dashed border — very light in both modes.
    private static var dashColor: UIColor {
        .quaternaryLabel
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        dashedLayer.path = UIBezierPath(
            roundedRect: dashedView.bounds,
            cornerRadius: 12
        ).cgPath

        dashedLayer.frame = dashedView.bounds
    }

    private func setupViews() {
        dashedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dashedView)

        NSLayoutConstraint.activate([
            dashedView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 4
            ),
            dashedView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 4
            ),
            dashedView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -4
            ),
            dashedView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -4
            )
        ])

        dashedLayer.fillColor = UIColor.clear.cgColor
        dashedLayer.strokeColor = Self.dashColor.cgColor
        dashedLayer.lineWidth = 1
        dashedLayer.lineDashPattern = [5, 4]

        dashedView.layer.addSublayer(dashedLayer)

        label.text = "Drop tasks here"
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center

        dashedView.addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(
                equalTo: dashedView.centerXAnchor
            ),
            label.centerYAnchor.constraint(
                equalTo: dashedView.centerYAnchor
            )
        ])
    }

    func configure(isEmpty: Bool) {
        isHidden = !isEmpty
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)

        dashedLayer.strokeColor = Self.dashColor.cgColor
    }
}
