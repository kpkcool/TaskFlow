//
//  TaskEditorViewController.swift
//  TaskFlow
//

import Combine
import UIKit

final class TaskEditorViewController: UIViewController {

    var onSaved: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDeleted: (() -> Void)?

    private let viewModel: TaskEditorViewModel
    private var cancellables = Set<AnyCancellable>()

    private let titleField: UITextField = {
        let field = UITextField()
        field.placeholder = "What needs to be done?"
        field.font = .preferredFont(forTextStyle: .headline)
        field.borderStyle = .none
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        return field
    }()

    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Add more detail (optional)"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .placeholderText
        return label
    }()

    private let statusSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: TaskStatus.allCases.map(\.displayName))
        return control
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = .preferredFont(forTextStyle: .footnote).semibold()
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let saveButton = UIBarButtonItem()
    private let scrollView = UIScrollView()

    init(viewModel: TaskEditorViewModel) {
        self.viewModel = viewModel
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
        view.backgroundColor = .systemGroupedBackground
        title = viewModel.navigationTitle

        setupNavigationBar()
        setupLayout()
        bindViewModel()

        titleField.text = viewModel.title
        descriptionTextView.text = viewModel.taskDescription
        placeholderLabel.isHidden = !viewModel.taskDescription.isEmpty
        statusSegmentedControl.selectedSegmentIndex = TaskStatus.allCases.firstIndex(of: viewModel.status) ?? 0
        updateSegmentedControlAppearance()

        titleField.addTarget(self, action: #selector(titleChanged), for: .editingChanged)
        descriptionTextView.delegate = self
        statusSegmentedControl.addTarget(self, action: #selector(statusChanged), for: .valueChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !viewModel.isEditing {
            titleField.becomeFirstResponder()
        }
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        saveButton.title = "Save"
        if #available(iOS 26.0, *) {
            saveButton.style = .prominent
        } else {
            saveButton.style = .done
        }
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        navigationItem.rightBarButtonItem = saveButton
    }

    private func setupLayout() {
        descriptionTextView.addSubview(placeholderLabel)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: descriptionTextView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: descriptionTextView.leadingAnchor)
        ])

        // Title's card also holds the validation error, directly under the
        // field it's complaining about — not stranded at the bottom of the
        // whole form where the user has to hunt for it.
        let titleCard = Self.card(
            icon: "pencil.line",
            label: "Title",
            content: UIStackView.vertical(spacing: 6, [titleField, errorLabel])
        )

        let descriptionCard = Self.card(
            icon: "text.alignleft",
            label: "Description",
            content: descriptionTextView
        )
        descriptionTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        let statusCard = Self.card(
            icon: "flag.fill",
            label: "Status",
            content: statusSegmentedControl
        )

        var cards: [UIView] = [titleCard, descriptionCard, statusCard]

        // Only show the delete button when editing an existing task — not
        // during creation (there's nothing to delete yet).
        if viewModel.isEditing {
            let deleteButton = Self.makeDeleteButton()
            deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
            cards.append(deleteButton)
        }

        let stack = UIStackView.vertical(spacing: 16, cards)

        // The form's natural height is much shorter than the screen. Pinning
        // the stack directly to all four safe-area edges would force
        // UIStackView to stretch its arranged subviews to eat the leftover
        // space. A scroll view lets the stack size itself naturally, scrolls
        // if Dynamic Type/the keyboard need the room, and never stretches.
        view.addSubview(scrollView)
        scrollView.keyboardDismissMode = .interactive
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
        stack.pinEdges(to: contentView, insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let convertedFrame = view.convert(endFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedFrame.minY - view.safeAreaInsets.bottom)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    private func bindViewModel() {
        viewModel.$validationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorLabel.text = message
                self?.errorLabel.isHidden = message == nil
            }
            .store(in: &cancellables)

        viewModel.$isSaving
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSaving in
                self?.saveButton.isEnabled = !isSaving
                self?.titleField.isEnabled = !isSaving
            }
            .store(in: &cancellables)
    }

    @objc private func titleChanged() {
        viewModel.title = titleField.text ?? ""
    }

    @objc private func statusChanged() {
        viewModel.status = TaskStatus.allCases[statusSegmentedControl.selectedSegmentIndex]
        updateSegmentedControlAppearance()
    }

    /// Tints the segmented control to match the currently selected status —
    /// the same blue/orange/green used for the section headers on the
    /// board, so status feels like one consistent visual language.
    private func updateSegmentedControlAppearance() {
        statusSegmentedControl.selectedSegmentTintColor = Self.color(for: viewModel.status)
        statusSegmentedControl.setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .subheadline).semibold(), .foregroundColor: UIColor.white],
            for: .selected
        )
        statusSegmentedControl.setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .subheadline).semibold()],
            for: .normal
        )
    }

    private static func color(for status: TaskStatus) -> UIColor {
        switch status {
        case .todo: return .systemBlue
        case .inProgress: return .systemOrange
        case .done: return .systemGreen
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        viewModel.save { [weak self] success in
            if success {
                self?.onSaved?()
            }
        }
    }

    @objc private func deleteTapped() {
        let alert = UIAlertController(
            title: "Delete \"\(viewModel.title)\"?",
            message: "This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteTask { success in
                if success {
                    self?.onDeleted?()
                }
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Card & button builders

    private static func makeDeleteButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = "Delete Task"
        config.image = UIImage(systemName: "trash")
        config.imagePadding = 6
        config.baseForegroundColor = .systemRed
        let button = UIButton(configuration: config)
        return button
    }

    private static func card(icon: String, label: String, content: UIView) -> UIView {
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .secondaryLabel
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).semibold()
        titleLabel.textColor = .label

        let header = UIStackView.horizontal(spacing: 8, [iconView, titleLabel])

        let card = UIStackView.vertical(spacing: 10, [header, content])
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        return card
    }
}

extension TaskEditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        viewModel.taskDescription = textView.text
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}

private extension UIFont {
    func semibold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        // `.traitBold` gets us weight parity across Dynamic Type sizes more
        // reliably than hand-building a `UIFontDescriptor` with `.semibold`,
        // and reads plenty "eye catching" at these form-label sizes.
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension UIStackView {
    static func vertical(spacing: CGFloat, _ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }

    static func horizontal(spacing: CGFloat, _ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.spacing = spacing
        stack.alignment = .center
        return stack
    }
}
