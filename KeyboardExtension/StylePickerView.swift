import UIKit

final class StylePickerView: UIView {
    var onSelect: ((Style) -> Void)?
    private let container = UIStackView()
    private let backdrop = UIControl()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Backdrop to dismiss when tapped
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        backdrop.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Card container
        container.axis = .vertical
        container.alignment = .fill
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.layer.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        card.addSubview(container)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.9),

            container.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        // Title
        let title = UILabel()
        title.text = "Choose Style"
        title.font = .boldSystemFont(ofSize: 16)
        container.addArrangedSubview(title)

        // Buttons for each style
        for s in Style.allCases {
            let b = UIButton(type: .system)
            b.setTitle(s.rawValue.capitalized, for: .normal)
            b.contentHorizontalAlignment = .leading
            b.titleLabel?.font = .systemFont(ofSize: 15)
            b.backgroundColor = .tertiarySystemBackground
            b.layer.cornerRadius = 8
            b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            b.addAction(UIAction { [weak self] _ in
                self?.onSelect?(s)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self?.dismiss(animated: true)
            }, for: .touchUpInside)
            container.addArrangedSubview(b)
        }

        // Cancel
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.contentHorizontalAlignment = .trailing
        cancel.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        container.addArrangedSubview(cancel)

        alpha = 0
    }

    func present(over parent: UIView) {
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(self)
        UIView.animate(withDuration: 0.18) { self.alpha = 1 }
    }

    func dismiss(animated: Bool) {
        let animations = { self.alpha = 0 }
        let completion: (Bool) -> Void = { _ in self.removeFromSuperview() }
        animated ? UIView.animate(withDuration: 0.18, animations: animations, completion: completion)
                 : { animations(); completion(true) }()
    }

    @objc private func dismissSelf() { dismiss(animated: true) }
}
