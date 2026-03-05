// StoreKitProvider.swift
// PaywallKit SDK
//
// Fallback провайдер на базі StoreKit 2.
// Повністю замінює CustomPaywallViewController / CustomPaywallDelegate.

import UIKit
import StoreKit

// MARK: - StoreKitProvider

/// Fallback провайдер — показує твій ViewController через StoreKit 2.
public final class StoreKitProvider: PaywallProvider {

    // MARK: - Dependencies

    private let productIds: [String]
    private let validator: SubscriptionValidator
    private let paywallFactory: StoreKitPaywallFactory
    private let accentColor: UIColor

    // MARK: - Init

    /// Ініціалізація з будь-якою фабрикою (для нестандартних випадків).
    public init(
        productIds: [String],
        validator: SubscriptionValidator,
        paywallFactory: StoreKitPaywallFactory,
        accentColor: UIColor = .systemBlue
    ) {
        self.productIds = productIds
        self.validator = validator
        self.paywallFactory = paywallFactory
        self.accentColor = accentColor
    }

    /// Зручний ініціалізатор — просто передай свій клас.
    ///
    /// ```swift
    /// StoreKitProvider(
    ///     productIds: ["com.app.premium"],
    ///     validator: subscriptionService,
    ///     uiType: MyPaywallViewController.self   // ← ось і все
    /// )
    /// ```
    public convenience init(
        productIds: [String],
        validator: SubscriptionValidator,
        uiType: any PaywallKitUI.Type,
        accentColor: UIColor = .systemBlue
    ) {
        self.init(
            productIds: productIds,
            validator: validator,
            paywallFactory: PaywallKitUIFactory(uiType: uiType),
            accentColor: accentColor
        )
    }

    // MARK: - PaywallProvider

    @MainActor
    public func present(placementId: String, from presenter: UIViewController) async -> PaywallResult {
        do {
            let products = try await loadProducts()
            guard !products.isEmpty else { return .failed(.noProducts) }
            return await showPaywall(products: products, placementId: placementId, from: presenter)
        } catch {
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    private func loadProducts() async throws -> [Product] {
        guard !productIds.isEmpty else { throw PaywallKitError.noProductIds }
        let products = try await Product.products(for: Set(productIds))
        return products.sorted { $0.price < $1.price }
    }

    @MainActor
    private func showPaywall(
        products: [Product],
        placementId: String,
        from presenter: UIViewController
    ) async -> PaywallResult {
        await withCheckedContinuation { continuation in
            let sink = SingleFireContinuation(continuation)

            // Bridge отримує state handler → пробрасує у factory → factory → context.onStateChange
            let eventBridge = StoreKitEventBridge(
                completion: sink,
                validator: validator,
                stateHandler: { [weak paywallFactory] state in
                    paywallFactory?.notifyState(state)
                }
            )

            let controller = paywallFactory.makeController(
                products: products,
                placementId: placementId,
                delegate: eventBridge,
                accentColor: accentColor
            )
            controller.modalPresentationStyle = .fullScreen

            // Bridge живе поки живе контролер
            eventBridge.retain(on: controller)
            presenter.present(controller, animated: true)
        }
    }
}

// MARK: - StoreKitPaywallFactory

/// Протокол фабрики paywall контролера.
///
/// Дефолтна реалізація — `PaywallKitUIFactory`.
/// Для нестандартних випадків — реалізуй цей протокол сам.
public protocol StoreKitPaywallFactory: AnyObject {

    /// Створює і повертає контролер.
    @MainActor
    func makeController(
        products: [Product],
        placementId: String,
        delegate: StoreKitPaywallDelegate,
        accentColor: UIColor
    ) -> UIViewController

    /// Bridge викликає при кожній зміні стану покупки.
    /// Фабрика пробрасує це в `context.onStateChange` → VC оновлює UI.
    func notifyState(_ state: PaywallUIState)
}

/// Default — no-op. Кастомна фабрика може не обробляти стан.
public extension StoreKitPaywallFactory {
    func notifyState(_ state: PaywallUIState) {}
}

// MARK: - StoreKitPaywallDelegate

/// Bridge між твоїм ViewController і логікою покупки.
/// Кличеться автоматично через `PaywallUIContext` — не треба реалізовувати руками.
public protocol StoreKitPaywallDelegate: AnyObject {
    func paywallDidRequestPurchase(_ product: Product, from controller: UIViewController)
    func paywallDidRequestRestore(from controller: UIViewController)
    func paywallDidClose(_ controller: UIViewController)
}

// MARK: - PaywallKitUIFactory

/// Дефолтна фабрика SDK.
///
/// Приймає будь-який `PaywallKitUI`-клас, будує `PaywallUIContext`
/// і з'єднує state updates bridge → context → VC.
///
/// **Що замінює:**
/// - `CustomPaywallViewController` (більше не потрібен)
/// - `CustomPaywallDelegate` (більше не потрібен)
/// - `DefaultStoreKitPaywallFactory` (більше не потрібен)
///
/// **Замість цього юзер реалізує лише `PaywallKitUI`.**
public final class PaywallKitUIFactory: StoreKitPaywallFactory {

    // MARK: - Properties

    private let uiType: any PaywallKitUI.Type

    /// Слабке посилання на context після створення контролера.
    /// `notifyState()` пише сюди → `onStateChange` → VC оновлює UI.
    private weak var activeContext: PaywallUIContext?

    // MARK: - Init

    public init(uiType: any PaywallKitUI.Type) {
        self.uiType = uiType
    }

    // MARK: - StoreKitPaywallFactory

    @MainActor
    public func makeController(
        products: [Product],
        placementId: String,
        delegate: StoreKitPaywallDelegate,
        accentColor: UIColor
    ) -> UIViewController {

        // 1. StoreKit.Product → PaywallProduct (VC не знає про StoreKit)
        var paywallProducts = products.map(PaywallProduct.init(from:))
        paywallProducts.markMostPopular()

        // 2. Weak ref на controller для delegate callbacks.
        //    Безпечна альтернатива UIApplication.topViewController.
        weak var controllerRef: UIViewController?

        // 3. Context — єдина точка контакту SDK ↔ VC.
        //    Три closure замість трьох методів делегата.
        let ctx = PaywallUIContext(
            products: paywallProducts,
            placementId: placementId,
            accentColor: accentColor,
            purchase: { [weak delegate] paywallProduct in
                guard
                    let original = products.first(where: { $0.id == paywallProduct.id }),
                    let vc = controllerRef
                else { return }
                delegate?.paywallDidRequestPurchase(original, from: vc)
            },
            restore: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidRequestRestore(from: vc)
            },
            close: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidClose(vc)
            }
        )

        // 4. Зберігаємо weak ref → notifyState() буде доставляти стани
        self.activeContext = ctx

        // 5. Твій ViewController отримує готовий context
        let controller = uiType.make(context: ctx)
        controllerRef = controller
        return controller
    }

    // MARK: - State relay  (Bridge → Factory → Context → VC)

    /// Викликається `StoreKitEventBridge` при кожній зміні стану.
    /// Пробрасуємо у `context.onStateChange` — VC отримує і оновлює UI.
    public func notifyState(_ state: PaywallUIState) {
        Task { @MainActor [weak self] in
            self?.activeContext?.onStateChange?(state)
        }
    }
}

// MARK: - StoreKitEventBridge

/// Обробляє StoreKit 2 покупку, валідацію і restore.
/// Повідомляє factory про зміни стану через `stateHandler`.
/// Юзер ніколи не взаємодіє з цим класом напряму.
final class StoreKitEventBridge: StoreKitPaywallDelegate {

    // MARK: - Dependencies

    private let completion: SingleFireContinuation<PaywallResult>
    private let validator: SubscriptionValidator
    /// Bridge → PaywallKitUIFactory.notifyState → context.onStateChange → VC
    private let stateHandler: (PaywallUIState) -> Void

    // MARK: - Init

    init(
        completion: SingleFireContinuation<PaywallResult>,
        validator: SubscriptionValidator,
        stateHandler: @escaping (PaywallUIState) -> Void
    ) {
        self.completion = completion
        self.validator = validator
        self.stateHandler = stateHandler
    }

    // MARK: - Lifetime

    func retain(on controller: UIViewController) {
        objc_setAssociatedObject(
            controller,
            &StoreKitEventBridge.retainKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    private static var retainKey: UInt8 = 0

    // MARK: - StoreKitPaywallDelegate

    func paywallDidRequestPurchase(_ product: Product, from controller: UIViewController) {
        Task { @MainActor in
            stateHandler(.purchasing(productId: product.id))      // VC: показати spinner
            let result = await executePurchase(product)

            switch result {
            case .cancelled:
                // Не закриваємо — юзер може обрати інший план або спробувати ще
                stateHandler(.idle)
                completion.resume(with: .cancelled)

            case .failed(let error):
                stateHandler(.error(error.localizedDescription))  // VC: показати помилку
                dismiss(controller) { self.completion.resume(with: result) }

            case .purchased, .restored, .alreadyPurchased:
                stateHandler(.success(result))                    // VC: SDK закриє сам
                dismiss(controller) { self.completion.resume(with: result) }
            }
        }
    }

    func paywallDidRequestRestore(from controller: UIViewController) {
        Task { @MainActor in
            stateHandler(.restoring)                              // VC: показати spinner
            let isActive = await validator.isSubscriptionActive()
            let result: PaywallResult = isActive ? .restored : .failed(.noActiveSubscription)

            if case .failed(let error) = result {
                stateHandler(.error(error.localizedDescription))
            } else {
                stateHandler(.success(result))
            }

            dismiss(controller) { self.completion.resume(with: result) }
        }
    }

    func paywallDidClose(_ controller: UIViewController) {
        dismiss(controller) { self.completion.resume(with: .cancelled) }
    }

    // MARK: - Purchase

    @MainActor
    private func executePurchase(_ product: Product) async -> PaywallResult {
        do {
            switch try await product.purchase() {
            case .success(let verification): return await handleVerification(verification)
            case .userCancelled:             return .cancelled
            case .pending:                   return .cancelled
            @unknown default:                return .failed(.unknown)
            }
        } catch {
            return .failed(.providerError(error))
        }
    }

    @MainActor
    private func handleVerification(_ verification: VerificationResult<Transaction>) async -> PaywallResult {
        switch verification {
        case .verified(let transaction):
            await transaction.finish()
            return await validator.isSubscriptionActive() ? .purchased : .failed(.subscriptionNotActive)
        case .unverified:
            return .failed(.verificationFailed)
        }
    }

    // MARK: - Helper

    private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
        controller.dismiss(animated: true, completion: completion)
    }
}

// MARK: - Array<PaywallProduct> helpers (internal)

private extension Array where Element == PaywallProduct {
    /// Позначає найдорожчий продукт як "popular" (зазвичай річний план).
    mutating func markMostPopular() {
        guard count > 1,
              let idx = indices.max(by: { self[$0].displayPrice < self[$1].displayPrice })
        else { return }
        self[idx].isPopular = true
    }
}
