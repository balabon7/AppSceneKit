// PaywallKit.swift
// PaywallKit SDK
//
// Основний клас SDK для управління paywall.

import UIKit

// MARK: - PaywallKit

/// Головний клас SDK. Singleton для зручності.
@MainActor
public final class PaywallKit {
    
    // MARK: - Singleton
    
    public static let shared = PaywallKit()
    private init() {}
    
    // MARK: - Configuration
    
    private var configuration: PaywallKitConfiguration?
    private var primaryProvider: PaywallProvider?
    private var fallbackProvider: PaywallProvider?
    private var validator: SubscriptionValidator?
    private var eventHandler: PurchaseEventHandler?
    private var logger: PaywallKitLogger = ConsoleLogger()

    // MARK: - Presentation lock

    /// Глобальний guard — запобігає паралельному показу двох paywall одночасно.
    /// Це трапляється коли action-paywall активний, а sceneDidBecomeActive
    /// намагається запустити launch-paywall (наприклад після dismiss App Store sheet).
    private var isPresenting = false
    
    // MARK: - Configure
    
    /// Конфігурує SDK з Adapty як основним провайдером і StoreKit як fallback.
    ///
    /// **Приклад:**
    /// ```swift
    /// PaywallKit.configure(
    ///     configuration: .init(productIds: ["com.app.premium.yearly"]),
    ///     primaryProvider: AdaptyProvider(validator: subscriptionService),
    ///     fallbackUI: MyPaywallViewController.self,  // ← твій UI для fallback
    ///     validator: subscriptionService
    /// )
    /// ```
    public static func configure(
        configuration: PaywallKitConfiguration,
        primaryProvider: PaywallProvider,
        fallbackUI: (any PaywallKitUI.Type)?,
        validator: SubscriptionValidator,
        eventHandler: PurchaseEventHandler? = nil
    ) {
        let fallbackProvider: StoreKitProvider? = fallbackUI.map {
            StoreKitProvider(
                productIds: configuration.productIds,
                validator: validator,
                uiType: $0,
                accentColor: configuration.accentColor
            )
        }
        
        shared.configure(
            configuration: configuration,
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }
    
    /// Повна конфігурація з кастомними провайдерами.
    public static func configure(
        configuration: PaywallKitConfiguration,
        primaryProvider: PaywallProvider,
        fallbackProvider: PaywallProvider?,
        validator: SubscriptionValidator,
        eventHandler: PurchaseEventHandler? = nil
    ) {
        shared.configure(
            configuration: configuration,
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }
    
    private func configure(
        configuration: PaywallKitConfiguration,
        primaryProvider: PaywallProvider,
        fallbackProvider: PaywallProvider?,
        validator: SubscriptionValidator,
        eventHandler: PurchaseEventHandler?
    ) {
        self.configuration = configuration
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.validator = validator
        self.eventHandler = eventHandler
        
        if let customLogger = configuration.logger {
            self.logger = customLogger
        }
        
        logger.log("PaywallKit configured", level: .info)
    }
    
    // MARK: - Present
    
    /// Показує paywall. Спочатку пробує Adapty, при помилці — fallback на StoreKit.
    ///
    /// **Приклад:**
    /// ```swift
    /// let result = await PaywallKit.present(
    ///     placementId: "onboarding",
    ///     from: self
    /// )
    /// if result.isSuccess {
    ///     // Юзер оформив підписку
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - placementId: ID placement з Adapty
    ///   - presenter: UIViewController з якого показати paywall
    ///   - forceShow: Якщо `true`, показує paywall навіть якщо є підписка (для відновлення/налаштувань). За замовчуванням `false`.
    @discardableResult
    public static func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false
    ) async -> PaywallResult {
        await shared.present(placementId: placementId, from: presenter, forceShow: forceShow)
    }
    
    /// Alias для `present()` — показує paywall.
    @discardableResult
    public static func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false
    ) async -> PaywallResult {
        await present(placementId: placementId, from: presenter, forceShow: forceShow)
    }
    
    // MARK: - Instance methods (для виклику через shared)
    
    /// Instance метод для виклику через `PaywallKit.shared.show()`.
    @discardableResult
    public func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false
    ) async -> PaywallResult {
        await Self.show(placementId: placementId, from: presenter, forceShow: forceShow)
    }
    
    private func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false
    ) async -> PaywallResult {
        guard configuration != nil else {
            logger.log("SDK not configured", level: .error)
            return .failed(.notConfigured)
        }

        // Глобальний guard проти паралельного показу.
        // Причина: sceneDidBecomeActive може спрацювати поки action-paywall ще активний
        // (після dismiss App Store sheet юзер повертається у foreground).
        guard !isPresenting else {
            logger.log("[\(placementId)] Skipped — another paywall is already presenting", level: .warning)
            return .cancelled
        }

        if !forceShow, let validator = validator {
            let hasActiveSubscription = await validator.isSubscriptionActive()
            if hasActiveSubscription {
                logger.log("User already has active subscription, skipping paywall", level: .info)
                return .alreadyPurchased
            }
        }

        if forceShow {
            logger.log("Presenting paywall for placement: \(placementId) (forceShow: true)", level: .info)
        } else {
            logger.log("Presenting paywall for placement: \(placementId)", level: .info)
        }

        isPresenting = true
        defer {
            isPresenting = false
            logger.log("[\(placementId)] Presentation lock released", level: .debug)
        }

        // 1. Пробуємо primary provider (Adapty)
        if let primary = primaryProvider {
            logger.log("Trying primary provider (Adapty)", level: .debug)
            logger.log("[\(placementId)] Presenter in window hierarchy: \(presenter.view.window != nil)", level: .debug)

            let result = await primary.present(placementId: placementId, from: presenter)
            
            switch result {
            case .purchased, .restored, .alreadyPurchased, .cancelled:
                logger.log("Primary provider result: \(result)", level: .info)
                handleResult(result)
                return result
                
            case .failed(let error):
                logger.log("Primary provider failed: \(error.localizedDescription)", level: .warning)
                // Падаємо на fallback
            }
        }
        
        // 2. Fallback на StoreKit з кастомним UI
        if let fallback = fallbackProvider {
            logger.log("Trying fallback provider (StoreKit)", level: .debug)
            logger.log("[\(placementId)] Presenter in window hierarchy: \(presenter.view.window != nil)", level: .debug)

            let result = await fallback.present(placementId: placementId, from: presenter)
            logger.log("Fallback provider result: \(result)", level: .info)
            handleResult(result)
            return result
        }
        
        // 3. Немає fallback — повертаємо помилку
        logger.log("No fallback provider configured", level: .error)
        return .failed(.noProducts)
    }
    
    // MARK: - Event handling
    
    private func handleResult(_ result: PaywallResult) {
        switch result {
        case .purchased, .restored, .alreadyPurchased:
            eventHandler?.onPurchaseSuccess(result: result)
        case .failed(let error):
            eventHandler?.onPurchaseFailure(error: error)
        case .cancelled:
            break
        }
    }
}
