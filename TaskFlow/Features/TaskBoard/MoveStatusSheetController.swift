//
//  MoveStatusSheetController.swift
//  TaskFlow
//
//  A centered modal card that replaces UIAlertController.actionSheet for the
//  "Move to..." swipe action. Presents as a dimmed overlay with a rounded
//  card in the center — color-coded status buttons matching the board
//  section headers (blue / orange / green).
//

import UIKit

final class MoveStatusSheetController: UIViewController {

    var onSelect: ((TaskStatus) -> Void)?
    var onCancel: (() -> Void)?

    private let task: Task
    private let cardView = UIView()
    private var didCallBack = false

    init(task: Task) {
        self.task = task
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(backgroundTapped)
        )
        tap.delegate = self
        view.addGestureRecognizer(tap)

        buildCard()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if !didCallBack {
            onCancel?()
        }
    }

    // MARK: - Actions

    @objc private func backgroundTapped() {
        dismissWithCancel()
    }

    private func dismissWithCancel() {
        didCallBack = true

        dismiss(animated: true) { [weak self] in
            self?.onCancel?()
        }
    }

    private func dismissWithSelection(_ status: TaskStatus) {
        didCallBack = true

        dismiss(animated: true) { [weak self] in
            self?.onSelect?(status)
        }
    }

    private func buildCard() {
        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 20
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.15
        cardView.layer.shadowRadius = 20
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)

        view.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            cardView.centerYAnchor.constraint(
                equalTo: view.centerYAnchor
            ),
            cardView.widthAnchor.constraint(
                equalTo: view.widthAnchor,
                multiplier: 0.82
            )
        ])

        let titleLabel = UILabel()
        titleLabel.text = "Move \"\(task.title)\""
        titleLabel.font = .preferredFont(
            forTextStyle: .headline
        )
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Choose a new status"
        subtitleLabel.font = .preferredFont(
            forTextStyle: .subheadline
        )
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        var buttons: [UIView] = []

        for status in TaskStatus.allCases where status != task.status {
            buttons.append(makeStatusButton(for: status))
        }

        let cancelButton = makeCancelButton()

        let stack = UIStackView(
            arrangedSubviews: [titleLabel, subtitleLabel] + buttons + [cancelButton]
        )
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)

        cardView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: cardView.topAnchor,
                constant: 24
            ),
            stack.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor,
                constant: 20
            ),
            stack.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor,
                constant: -20
            ),
            stack.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor,
                constant: -20
            )
        ])
    }

    private func makeStatusButton(for status: TaskStatus) -> UIButton {
        var config = UIButton.Configuration.filled()

        config.title = status.displayName
        config.image = UIImage(
            systemName: Self.icon(for: status)
        )
        config.imagePadding = 10
        config.cornerStyle = .large
        config.buttonSize = .large
        config.baseBackgroundColor = Self.color(for: status)
        config.baseForegroundColor = .white

        let button = UIButton(configuration: config)

        button.addAction(
            UIAction { [weak self] _ in
                self?.dismissWithSelection(status)
            },
            for: .touchUpInside
        )

        return button
    }

    private func makeCancelButton() -> UIButton {
        var config = UIButton.Configuration.plain()

        config.title = "Cancel"
        config.buttonSize = .large
        config.baseForegroundColor = .secondaryLabel

        let button = UIButton(configuration: config)

        button.addAction(
            UIAction { [weak self] _ in
                self?.dismissWithCancel()
            },
            for: .touchUpInside
        )

        return button
    }

    private static func color(for status: TaskStatus) -> UIColor {
        switch status {
        case .todo:
            return .systemBlue

        case .inProgress:
            return .systemOrange

        case .done:
            return .systemGreen
        }
    }

    private static func icon(for status: TaskStatus) -> String {
        switch status {
        case .todo:
            return "tray"

        case .inProgress:
            return "bolt.fill"

        case .done:
            return "checkmark.circle.fill"
        }
    }
}

extension MoveStatusSheetController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Only dismiss on taps outside the card
        !cardView.bounds.contains(
            touch.location(in: cardView)
        )
    }
}
