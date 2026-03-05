// PaywallProvider.swift
// PaywallKit SDK
//
// Protocol-based abstraction. Підстав Adapty, RevenueCat, або власний провайдер.

import UIKit

// MARK: - PaywallProvider

/// Абстракція провайдера paywall.
/// Реалізуй цей протокол щоб підключити будь-який SDK: Adapty, RevenueCat, тощо.
public protocol PaywallProvider: AnyObject, Sendable {

    /// Показує paywall для заданого `placementId`.
    /// - Returns: `PaywallResult` після завершення (покупка / відновлення / скасування / помилка).
    @MainActor
    func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> PaywallResult
}

// MARK: - SubscriptionValidator

/// Протокол для перевірки активності підписки після покупки.
/// Відокремлений від провайдера — можна використовувати з будь-яким бекендом.
public protocol SubscriptionValidator: AnyObject, Sendable {

    /// Перевіряє чи є активна підписка. Може робити мережевий запит.
    @MainActor
    func isSubscriptionActive() async -> Bool
}

// MARK: - PurchaseEventHandler

/// Протокол для обробки подій покупки (аналітика, UI-оновлення, тощо).
public protocol PurchaseEventHandler: AnyObject {

    /// Викликається одразу після успішної покупки або відновлення.
    @MainActor
    func onPurchaseSuccess(result: PaywallResult)

    /// Викликається після будь-якої помилки.
    @MainActor
    func onPurchaseFailure(error: PaywallKitError)
}

// Дефолтна реалізація — event handler необов'язковий.
public extension PurchaseEventHandler {
    func onPurchaseSuccess(result: PaywallResult) {}
    func onPurchaseFailure(error: PaywallKitError) {}
}
