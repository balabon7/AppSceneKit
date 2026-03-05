// DefaultPaywallAdapter.swift
// AppSceneKit SDK
//
// Простий, чистий paywall без зображень і trial toggle.
// Підключається одним рядком: fallbackUI: DefaultPaywallAdapter.self

import UIKit

// MARK: - DefaultPaywallAdapter

final class DefaultPaywallAdapter: UIViewController, PaywallKitUI, UIAdaptivePresentationControllerDelegate, UISheetPresentationControllerDelegate {

    // MARK: - PaywallKitUI

    static func make(context: PaywallUIContext) -> UIViewController {
        let vc = DefaultPaywallAdapter()
        vc.context = context
        
        // Повноекранний режим для onboarding/launch
        vc.modalPresentationStyle = .fullScreen
        
        // Для pageSheet/formSheet режиму розкоментуйте:
        // vc.modalPresentationStyle = .pageSheet
        // if #available(iOS 15.0, *) {
        //     if let sheet = vc.sheetPresentationController {
        //         sheet.detents = [.large()]
        //         sheet.prefersGrabberVisible = true
        //         sheet.delegate = vc
        //     }
        // } else {
        //     vc.presentationController?.delegate = vc
        // }
        
        return vc
    }

    // MARK: - Properties

    private var context: PaywallUIContext!
    private var selectedProduct: PaywallProduct?
    private var planButtons: [PlanButton] = []
    private var didClose = false  // Запобігаємо подвійному виклику close()
    
    // Акцентний колір (з context)
    private var accentColor: UIColor { context.accentColor }

    // MARK: - UI

    private lazy var closeButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        b.tintColor = .tertiaryLabel
        b.backgroundColor = .clear
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return b
    }()

    private lazy var headingStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        s.axis = .vertical
        s.spacing = 8
        s.alignment = .center
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Unlock Premium"
        l.font = .systemFont(ofSize: 28, weight: .bold)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Full access. Cancel anytime."
        l.font = .systemFont(ofSize: 15)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private lazy var plansStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 10
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var continueButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Continue", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .disabled)
        b.backgroundColor = self.accentColor
        b.layer.cornerRadius = 16
        b.layer.cornerCurve = .continuous
        b.isEnabled = false
        b.alpha = 0.5
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return b
    }()

    private lazy var bottomStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [termsButton, privacyButton, restoreButton])
        s.axis = .horizontal
        s.spacing = 0
        s.distribution = .fillEqually
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var termsButton   = makeTextButton("Terms of Use",   action: #selector(termsTapped))
    private lazy var privacyButton = makeTextButton("Privacy Policy", action: #selector(privacyTapped))
    private lazy var restoreButton = makeTextButton("Restore",        action: #selector(restoreTapped))

    private lazy var loadingOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        buildPlanButtons()
        selectDefault()
        observeState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Якщо view controller закривається (свайп вниз або інший спосіб)
        // і ми ще не викликали close(), викликаємо його зараз
        if isBeingDismissed && !didClose {
            didClose = true
            context.close()
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Викликається коли користувач закриває через gesture (свайп вниз)
        if !didClose {
            didClose = true
            context.close()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        view.backgroundColor = .systemBackground

        [headingStack, plansStack, continueButton, bottomStack, loadingOverlay]
            .forEach { view.addSubview($0) }
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([

            // Close — top right
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            // Heading — center верхньої третини
            headingStack.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 20),
            headingStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headingStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            // Plans — під heading, з гнучким відступом
            plansStack.topAnchor.constraint(greaterThanOrEqualTo: headingStack.bottomAnchor, constant: 28),
            plansStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            plansStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Continue — одразу під plans
            continueButton.topAnchor.constraint(equalTo: plansStack.bottomAnchor, constant: 20),
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            continueButton.heightAnchor.constraint(equalToConstant: 54),

            // Bottom — притиснутий до safeArea
            bottomStack.topAnchor.constraint(equalTo: continueButton.bottomAnchor, constant: 12),
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // Loading overlay
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Plan Buttons

    private func buildPlanButtons() {
        context.products.enumerated().forEach { index, product in
            let btn = PlanButton(product: product, accentColor: accentColor)
            btn.tag = index
            btn.addTarget(self, action: #selector(planTapped(_:)), for: .touchUpInside)
            plansStack.addArrangedSubview(btn)
            planButtons.append(btn)

            NSLayoutConstraint.activate([
                btn.heightAnchor.constraint(equalToConstant: 72)
            ])
        }
    }

    private func selectDefault() {
        let product = context.products.first(where: { $0.isPopular }) ?? context.products.first
        guard let product else { return }
        select(product)
    }

    private func select(_ product: PaywallProduct) {
        selectedProduct = product
        planButtons.forEach { $0.setSelected($0.tag == context.products.firstIndex(where: { $0.id == product.id }) ?? -1) }

        // Оновлюємо CTA кнопку
        let title = product.introductoryOffer != nil
            ? "Try Free & Subscribe"
            : "Continue"
        UIView.performWithoutAnimation {
            continueButton.setTitle(title, for: .normal)
            continueButton.layoutIfNeeded()
        }

        continueButton.isEnabled = true
        UIView.animate(withDuration: 0.2) { self.continueButton.alpha = 1 }
    }

    // MARK: - State

    private func observeState() {
        context.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    private func apply(_ state: PaywallUIState) {
        switch state {
        case .idle:
            setLoading(false)

        case .purchasing, .restoring, .loading:
            setLoading(true)

        case .success:
            setLoading(false) // SDK закриє сам

        case .error(let message):
            setLoading(false)
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        continueButton.isEnabled = !loading
        planButtons.forEach { $0.isUserInteractionEnabled = !loading }
    }

    // MARK: - Actions

    @objc private func planTapped(_ sender: PlanButton) {
        let product = context.products[sender.tag]
        select(product)
    }

    @objc private func continueTapped() {
        guard let product = selectedProduct else { return }
        context.purchase(product)
    }

    @objc private func restoreTapped() {
        context.restore()
    }

    @objc private func closeTapped() {
        didClose = true
        context.close()
    }

    @objc private func termsTapped() {
        openURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    @objc private func privacyTapped() {
        openURL("https://telegra.ph/Privacy-Policy--PDF-Scanner-Scan--Sign-Doc-03-05")
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    private func makeTextButton(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.titleLabel?.numberOfLines = 2
        b.titleLabel?.textAlignment = .center
        b.titleLabel?.lineBreakMode = .byWordWrapping
        b.setTitleColor(.tertiaryLabel, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }
}

// MARK: - PlanButton

private final class PlanButton: UIControl {

    // MARK: - Properties

    let product: PaywallProduct
    private let accentColor: UIColor
    private var isSelectedState = false

    // MARK: - UI

    private lazy var container: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 16
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.clear.cgColor
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .label
        return l
    }()

    private lazy var detailLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        return l
    }()

    private lazy var priceLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    private lazy var checkmark: UIImageView = {
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg))
        iv.tintColor = self.accentColor
        iv.alpha = 0  // Замість isHidden використовуємо alpha
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // "MOST POPULAR" badge — показується тільки для isPopular
    private lazy var popularBadge: PaddedLabel = {
        let l = PaddedLabel()
        l.text = "BEST VALUE"
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.backgroundColor = self.accentColor
        l.layer.cornerRadius = 6
        l.layer.cornerCurve = .continuous
        l.layer.masksToBounds = true
        l.isHidden = !product.isPopular
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Init

    init(product: PaywallProduct, accentColor: UIColor) {
        self.product = product
        self.accentColor = accentColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupUI() {
        addSubview(container)
        addSubview(popularBadge)

        // Left stack: name + detail
        let leftStack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 3

        // Row: leftStack | price | checkmark
        let row = UIStackView(arrangedSubviews: [leftStack, priceLabel, checkmark])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        // Checkmark фіксований розмір для резервування місця
        checkmark.setContentHuggingPriority(.required, for: .horizontal)
        checkmark.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceLabel.setContentHuggingPriority(.required, for: .horizontal)
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        container.addSubview(row)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 6),  // залишаємо місце для badge
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),

            // Фіксована ширина для галочки, щоб зарезервувати місце
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),

            // Badge — виступає вгору над container
            popularBadge.centerYAnchor.constraint(equalTo: container.topAnchor),
            popularBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        ])
    }

    private func configure() {
        nameLabel.text = product.displayName

        // Деталь: period або offer
        if let offer = product.introductoryOffer {
            detailLabel.text = offer
            detailLabel.textColor = self.accentColor
        } else if let perMonth = product.pricePerMonth {
            detailLabel.text = perMonth
        } else {
            detailLabel.text = product.subscriptionPeriod.displayString
        }

        priceLabel.text = product.displayPrice
    }

    // MARK: - Selection

    func setSelected(_ selected: Bool) {
        isSelectedState = selected

        UIView.animate(withDuration: 0.2, delay: 0.2, options: .curveEaseInOut) {
            if selected {
                self.container.backgroundColor = self.accentColor.withAlphaComponent(0.07)
                self.container.layer.borderColor = self.accentColor.cgColor
                self.nameLabel.textColor = .label
                self.priceLabel.textColor = self.accentColor
                self.checkmark.alpha = 1  // Показуємо галочку
            } else {
                self.container.backgroundColor = .secondarySystemBackground
                self.container.layer.borderColor = UIColor.clear.cgColor
                self.nameLabel.textColor = .label
                self.priceLabel.textColor = .secondaryLabel
                self.checkmark.alpha = 0  // Ховаємо галочку, але місце залишається
            }
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.1) {
            self.container.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.12, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 4) {
            self.container.transform = .identity
        }
        sendActions(for: .touchUpInside)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.1) { self.container.transform = .identity }
    }
}

// MARK: - PaddedLabel

private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(
            width:  s.width  + insets.left + insets.right,
            height: s.height + insets.top  + insets.bottom
        )
    }
}
// MARK: - SubscriptionPeriod Extension

private extension SubscriptionPeriod {
    var displayString: String {
        switch self {
        case .weekly:    return "Weekly"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly:    return "Yearly"
        case .lifetime:  return "Lifetime"
        case .unknown:   return ""
        }
    }
}

