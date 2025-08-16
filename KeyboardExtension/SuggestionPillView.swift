import UIKit

final class SuggestionPill: UIView {
    private let label = UILabel()
    private var action: (() -> Void)?

    init(text: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.action = action
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 16
        layer.masksToBounds = true
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
        accessibilityLabel = text
    }

    @objc private func didTap() { action?() }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
