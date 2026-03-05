// AdaptyProvider.swift
// AppSceneKit SDK
//
// Реалізація PaywallProvider для Adapty SDK.
// Ізольована від решти SDK — заміна займе 5 хвилин.

import UIKit
import Adapty
import AdaptyUI

// MARK: - AdaptyProvider

/// Провайдер на базі Adapty SDK.
/// Конформить до `PaywallProvider` — повністю замінний.
public final class AdaptyProvider: PaywallProvider {

    // MARK: - Dependencies

    private let validator: SubscriptionValidator
    private let fetchTimeout: TimeInterval

    // MARK: - Init

    public init(
        validator: SubscriptionValidator,
        fetchTimeout: TimeInterval = 15.0
    ) {
        self.validator = validator
        self.fetchTimeout = fetchTimeout
    }

    // MARK: - PaywallProvider

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> PaywallResult {
        do {
            // 1. Завантажуємо paywall і продукти паралельно де можливо
            let paywall = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywall(placementId: placementId)
            }

            let products = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywallProducts(paywall: paywall)
            }

            // 2. Будуємо конфігурацію
            let configuration = try await AdaptyUI.getPaywallConfiguration(
                forPaywall: paywall,
                loadTimeout: nil,
                products: products,
                observerModeResolver: nil,
                tagResolver: nil,
                timerResolver: nil,
                assetsResolver: nil
            )

            // 3. Показуємо UI через continuation
            return await showController(configuration: configuration, from: presenter)

        } catch let error as PaywallKitError {
            return .failed(error)
        } catch {
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    @MainActor
    private func showController(
        configuration: AdaptyUI.PaywallConfiguration,
        from presenter: UIViewController
    ) async -> PaywallResult {
        // UIViewController.present() тихо провалюється якщо presenter не в ієрархії вікна
        // (лише лог у консолі, без throw/callback) — continuation зависне назавжди.
        // Тому перевіряємо заздалегідь і повертаємо .failed щоб PaywallKit міг піти у fallback.
        guard presenter.view.window != nil else {
            return .failed(.providerError(
                NSError(
                    domain: "PaywallKit",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Presenter is not in the window hierarchy"]
                )
            ))
        }

        return await withCheckedContinuation { continuation in
            let completionHandler = SingleFireContinuation(continuation)
            let delegate = AdaptyEventBridge(
                completion: completionHandler,
                validator: validator
            )

            do {
                let controller = try AdaptyUI.paywallController(
                    with: configuration,
                    delegate: delegate,
                    showDebugOverlay: false
                )
                controller.modalPresentationStyle = .fullScreen

                // Прив'язуємо delegate до controller — безпечно, без objc_setAssociatedObject
                delegate.retain(on: controller)

                presenter.present(controller, animated: true)
            } catch {
                completionHandler.resume(with: .failed(.providerError(error)))
            }
        }
    }

    // MARK: - Timeout

    private func withTimeout<T>(
        _ seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PaywallKitError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

// MARK: - AdaptyEventBridge

/// Отримує події від AdaptyUI і конвертує їх у `PaywallResult`.
/// Живе рівно стільки, скільки контролер — без зовнішніх утримувачів.
private final class AdaptyEventBridge: NSObject, AdaptyPaywallControllerDelegate {

    private let completion: SingleFireContinuation<PaywallResult>
    private let validator: SubscriptionValidator

    init(completion: SingleFireContinuation<PaywallResult>, validator: SubscriptionValidator) {
        self.completion = completion
        self.validator = validator
    }

    /// Прив'язує self до UIViewController через AssociatedObject.
    /// Це єдине місце де ми використовуємо objc runtime — і це виправдано.
    func retain(on controller: UIViewController) {
        objc_setAssociatedObject(
            controller,
            &AdaptyEventBridge.retainKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    private static var retainKey: UInt8 = 0

    // MARK: - Purchase

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        Task { @MainActor in
            guard let profile = purchaseResult.profile else {
                // Adapty викликає didFinishPurchase з nil profile коли юзер скасовує
                // Apple ID / password sheet — транзакція не завершилась.
                // Залишаємо paywall відкритим (як didFailPurchase з .paymentCancelled).
                // НЕ resume-имо continuation — юзер може спробувати ще або закрити сам.
                print("[PaywallKit][debug] didFinishPurchase: nil profile for '\(product.vendorProductId)' — Apple ID sheet cancelled. Keeping paywall open.")
                return
            }

            // Застосовуємо профіль до SubscriptionService
            if let service = validator as? ProfileApplicable {
                service.apply(profile: profile)
            }

            // Перевіряємо активацію
            let premiumIsActive = profile.accessLevels["premium"]?.isActive == true
            let validatorIsActive = await validator.isSubscriptionActive()
            let isActive = premiumIsActive || validatorIsActive

            dismiss(controller) {
                self.completion.resume(with: isActive ? .purchased : .failed(.subscriptionNotActive))
            }
        }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        // Скасування юзером — залишаємо paywall відкритим
        guard error.adaptyErrorCode != .paymentCancelled else { return }

        dismiss(controller) {
            self.completion.resume(with: .failed(.providerError(error)))
        }
    }

    // MARK: - Restore

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishRestoreWith profile: AdaptyProfile
    ) {
        Task { @MainActor in
            if let service = validator as? ProfileApplicable {
                service.apply(profile: profile)
            }
            let isActive = profile.accessLevels["premium"]?.isActive == true
            dismiss(controller) {
                self.completion.resume(with: isActive ? .restored : .failed(.noActiveSubscription))
            }
        }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRestoreWith error: AdaptyError
    ) {
        dismiss(controller) {
            self.completion.resume(with: .failed(.providerError(error)))
        }
    }

    // MARK: - Actions

    func paywallController(
        _ controller: AdaptyPaywallController,
        didPerform action: AdaptyUI.Action
    ) {
        switch action {
        case .close:
            dismiss(controller) { self.completion.resume(with: .cancelled) }

        case .openURL(let url):
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)

        case .custom:
            break
        }
    }

    // MARK: - Errors (non-fatal)

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRenderingWith error: AdaptyUIError
    ) {
        dismiss(controller) { self.completion.resume(with: .failed(.providerError(error))) }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailLoadingProductsWith error: AdaptyError
    ) -> Bool {
        return true // Дозволяємо показати paywall без цін
    }

    // MARK: - Lifecycle (no-op — додай логгер якщо потрібно)

    func paywallControllerDidAppear(_ controller: AdaptyPaywallController) {}
    func paywallControllerDidDisappear(_ controller: AdaptyPaywallController) {}
    func paywallController(_ controller: AdaptyPaywallController, didSelectProduct product: AdaptyPaywallProductWithoutDeterminingOffer) {}
    func paywallController(_ controller: AdaptyPaywallController, didStartPurchase product: AdaptyPaywallProduct) {}
    func paywallControllerDidStartRestore(_ controller: AdaptyPaywallController) {}
    func paywallController(_ controller: AdaptyPaywallController, didPartiallyLoadProducts failedIds: [String]) {}
    func paywallController(_ controller: AdaptyPaywallController, didFinishWebPaymentNavigation product: AdaptyPaywallProduct?, error: AdaptyError?) {}

    // MARK: - Helper

    private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
        controller.dismiss(animated: true, completion: completion)
    }
}

// MARK: - ProfileApplicable

/// Опціональний протокол для SubscriptionValidator що вміє приймати AdaptyProfile.
/// Дозволяє bridge між Adapty і твоїм сервісом без hard dependency.
public protocol ProfileApplicable {
    func apply(profile: AdaptyProfile)
}
