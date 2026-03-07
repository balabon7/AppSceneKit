// RatingPromptViewController.swift
// AppSceneKit
//
// Pre-prompt з зірками перед Apple's SKStoreReviewController.
// 4-5 зірок → Apple prompt. 1-3 зірки → feedback URL.

import UIKit

// MARK: - RatingPromptViewController

final class RatingPromptViewController: UIViewController {

    // MARK: - Properties

    private let configuration: RatingKitConfiguration
    private let onResult: (RatingResult) -> Void
    private var isAnswered = false

    // MARK: - Init

    init(configuration: RatingKitConfiguration, onResult: @escaping (RatingResult) -> Void) {
        self.configuration = configuration
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private let dimView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        v.alpha = 0
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let alertView: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 20
        v.layer.masksToBounds = false
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.4
        v.layer.shadowRadius = 20
        v.layer.shadowOffset = CGSize(width: 0, height: 10)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let messageLabel: UILabel = {
        let l = UILabel()
        l.text = "Enjoying the app? Your rating helps us improve."
        l.textAlignment = .center
        l.numberOfLines = 0
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let thanksLabel: UILabel = {
        let l = UILabel()
        l.text = "Thanks for your feedback!"
        l.textAlignment = .center
        l.textColor = .label
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.alpha = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var starsView: RatingStarsView = {
        let v = RatingStarsView(stars: 5, initial: 0)
        v.onChange = { [weak self] _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            self?.updateSubmitEnabled()
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let cancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Not now", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.setTitleColor(.secondaryLabel, for: .normal)
        b.layer.cornerRadius = 12
        b.layer.borderWidth = 1.5
        b.layer.borderColor = UIColor.secondaryLabel.withAlphaComponent(0.25).cgColor
        b.backgroundColor = .clear
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let submitButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Submit", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = .systemBlue
        b.layer.cornerRadius = 12
        b.layer.masksToBounds = true
        b.isEnabled = false
        b.alpha = 0.4
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        titleLabel.text = "Rate PDF Editor My Docs"
        buildUI()
        layoutUI()
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        submitButton.addTarget(self, action: #selector(submitPressed), for: .touchUpInside)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateIn()
    }

    // MARK: - Build & Layout

    private func buildUI() {
        view.addSubview(dimView)
        view.addSubview(alertView)
        [titleLabel, messageLabel, starsView, thanksLabel, cancelButton, submitButton]
            .forEach { alertView.addSubview($0) }
    }

    private func layoutUI() {
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            alertView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            alertView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            alertView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            alertView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: alertView.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -24),

            starsView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            starsView.centerXAnchor.constraint(equalTo: alertView.centerXAnchor),
            starsView.heightAnchor.constraint(equalToConstant: 44),

            thanksLabel.topAnchor.constraint(equalTo: starsView.bottomAnchor, constant: 12),
            thanksLabel.centerXAnchor.constraint(equalTo: alertView.centerXAnchor),

            cancelButton.topAnchor.constraint(equalTo: thanksLabel.bottomAnchor, constant: 20),
            cancelButton.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 20),
            cancelButton.heightAnchor.constraint(equalToConstant: 48),

            submitButton.topAnchor.constraint(equalTo: thanksLabel.bottomAnchor, constant: 20),
            submitButton.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -20),
            submitButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),
            submitButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor),
            submitButton.heightAnchor.constraint(equalToConstant: 48),
            submitButton.bottomAnchor.constraint(equalTo: alertView.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Submit enable/disable

    private func updateSubmitEnabled() {
        guard !submitButton.isEnabled else { return }
        submitButton.isEnabled = true
        UIView.animate(withDuration: 0.2) { self.submitButton.alpha = 1 }
    }

    // MARK: - Animations

    private func animateIn() {
        alertView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        alertView.alpha = 0

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.dimView.alpha = 1
            self.alertView.transform = .identity
            self.alertView.alpha = 1
        }
    }

    private func animateOut(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25) {
            self.alertView.alpha = 0
            self.alertView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.dimView.alpha = 0
        } completion: { _ in completion?() }
    }

    // MARK: - Actions

    @objc private func submitPressed() {
        guard !isAnswered else { return }
        let rating = starsView.rating

        if rating >= 4 {
            // 4-5 зірок → Apple Review
            isAnswered = true
            animateOut {
                self.dismiss(animated: false) { self.onResult(.positive) }
            }
        } else {
            // 1-3 зірки → thanks → feedback
            isAnswered = true
            starsView.isUserInteractionEnabled = false
            submitButton.isEnabled = false

            UIView.animate(withDuration: 0.2) {
                self.thanksLabel.alpha = 1
                self.submitButton.alpha = 0.3
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.animateOut {
                    self.dismiss(animated: false) { self.onResult(.negative) }
                }
            }
        }
    }

    @objc private func cancelPressed() {
        guard !isAnswered else { return }
        isAnswered = true
        animateOut {
            self.dismiss(animated: false) { self.onResult(.dismissed) }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !isAnswered {
            isAnswered = true
            onResult(.dismissed)
        }
    }
}

// MARK: - RatingStarsView

/// Рядок з 5 зірок. Жовтий колір, bounce анімація, haptic на кожному тапі.
final class RatingStarsView: UIStackView {

    var onChange: ((Int) -> Void)?

    private(set) var rating: Int {
        didSet { updateStars() }
    }

    private var buttons: [UIButton] = []
    private let total: Int

    // Той самий жовтий що в RateAppViewController
    private let starColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)

    init(stars: Int = 5, initial: Int = 0) {
        self.total = max(1, stars)
        self.rating = max(0, min(stars, initial))
        super.init(frame: .zero)

        axis = .horizontal
        alignment = .center
        distribution = .fillEqually
        spacing = 8

        setupStars()
        updateStars()
    }

    required init(coder: NSCoder) { fatalError() }

    private func setupStars() {
        for i in 1...total {
            let b = UIButton(type: .system)
            b.tag = i
            b.tintColor = starColor
            let cfg = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
            b.setPreferredSymbolConfiguration(cfg, forImageIn: .normal)
            b.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            b.accessibilityLabel = "\(i) star\(i > 1 ? "s" : "")"
            b.accessibilityTraits = [.button]
            buttons.append(b)
            addArrangedSubview(b)
        }
    }

    private func updateStars() {
        for (idx, btn) in buttons.enumerated() {
            let filled = idx < rating

            // Bounce на кожній заповненій зірці
            if filled {
                UIView.animate(
                    withDuration: 0.15,
                    delay: Double(idx) * 0.04,
                    usingSpringWithDamping: 0.5,
                    initialSpringVelocity: 6
                ) {
                    btn.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                } completion: { _ in
                    UIView.animate(withDuration: 0.12) { btn.transform = .identity }
                }
            }

            UIView.transition(with: btn, duration: 0.12, options: .transitionCrossDissolve) {
                btn.setImage(UIImage(systemName: filled ? "star.fill" : "star"), for: .normal)
                btn.tintColor = filled ? self.starColor : .secondaryLabel.withAlphaComponent(0.25)
            }
        }
    }

    @objc private func tap(_ sender: UIButton) {
        rating = sender.tag
        onChange?(rating)
    }
}
