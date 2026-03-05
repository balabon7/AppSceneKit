// PaywallKit+Example.swift
// PaywallKit SDK — Integration Guide
//
// Цей файл НЕ входить в SDK. Це приклад інтеграції для твого додатку.

/*
import UIKit
import Adapty

// MARK: - Step 1: Реалізуй SubscriptionValidator

/// Твій існуючий SubscriptionService конформить до SubscriptionValidator.
/// Просто додай extension — жодних змін у самому класі.
extension SubscriptionService: SubscriptionValidator {

    public func isSubscriptionActive() async -> Bool {
        // Використовуй свою існуючу логіку
        return await hasAnyActiveForceReload()
    }
}

/// Якщо використовуєш Adapty profiles — конформись до ProfileApplicable
extension SubscriptionService: ProfileApplicable {
    public func apply(profile: AdaptyProfile) {
        // Твоя логіка збереження профілю
    }
}

// MARK: - Step 2: Конфігурація (AppDelegate або @main App)

final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Ініціалізуй Adapty як зазвичай
        Adapty.activate("YOUR_ADAPTY_API_KEY")

        let validator = SubscriptionService.shared

        // Конфігуруй PaywallKit один раз
        PaywallKit.configure(
            configuration: .init(
                productIds: ["com.app.premium.monthly", "com.app.premium.yearly"],
                fetchTimeout: 12.0,
                logger: ConsoleLogger() // або власний логгер
            ),
            primaryProvider: AdaptyProvider(validator: validator),
            fallbackUI: MyPaywallViewController.self,  // ← твій кастомний UI для fallback
            validator: validator,
            eventHandler: AnalyticsEventHandler() // опціональний
        )

        return true
    }
}

// MARK: - Step 3: Показ paywall

final class OnboardingViewController: UIViewController {

    func showPremium() {
        Task {
            // SDK спочатку спробує показати Adapty paywall з placementId,
            // якщо помилка — покаже MyPaywallViewController через StoreKit
            let result = await PaywallKit.present(
                placementId: "onboarding",
                from: self
            )

            switch result {
            case .purchased:
                navigateToMainScreen()
            case .restored:
                showRestoredBanner()
            case .cancelled:
                break // Юзер закрив — нічого не робимо
            case .failed(let error):
                showError(error)
            }
        }
    }
}

// MARK: - Step 4: Аналітика через PurchaseEventHandler (опціонально)

final class AnalyticsEventHandler: PurchaseEventHandler {

    func onPurchaseSuccess(result: PaywallResult) {
        // Firebase.logEvent("purchase_success")
        // AppsFlyerLib.shared().logEvent("af_purchase", withValues: [...])
    }

    func onPurchaseFailure(error: PaywallKitError) {
        // Crashlytics.crashlytics().record(error: error)
    }
}

// MARK: - Як працює fallback система
 
 Коли викликаєш PaywallKit.present(placementId: "onboarding", from: self):
 
 1. SDK спочатку пробує AdaptyProvider.present()
    - Завантажує paywall config з Adapty
    - Показує нативний Adapty UI
    - Якщо успіх → повертає .purchased/.restored
 
 2. Якщо Adapty провалився (timeout, no network, etc):
    - SDK автоматично переключається на StoreKitProvider
    - Завантажує продукти з App Store Connect
    - Показує твій MyPaywallViewController через PaywallKitUI
    - Обробляє покупку через StoreKit 2
 
 3. placementId передається у твій UI через context.placementId
    - Можеш використати для аналітики
    - Або для різних варіантів UI (onboarding vs settings)
 
 Твій MyPaywallViewController нічого не знає про Adapty чи StoreKit —
 він просто отримує PaywallUIContext з продуктами та callbacks.
 
 */
