// SubscriptionService.swift
// DocScanPro
//
// Простий сервіс для перевірки підписки.
// Конформить до SubscriptionValidator для PaywallKit.

import Foundation
import Adapty
import StoreKit

/// Сервіс для перевірки статусу підписки.
@MainActor
final class SubscriptionService: SubscriptionValidator {
    
    static let shared = SubscriptionService()
    private init() {}
    
    // MARK: - Adapty Profile (опціонально)
    
    private var cachedProfile: AdaptyProfile?
    
    // MARK: - SubscriptionValidator
    
    /// Перевіряє чи є активна підписка.
    public func isSubscriptionActive() async -> Bool {
        // 1. Спочатку перевіряємо кешований Adapty профіль
        if let profile = cachedProfile,
           profile.accessLevels["premium"]?.isActive == true {
            return true
        }
        
        // 2. Пробуємо отримати свіжий профіль з Adapty
        do {
            let profile = try await Adapty.getProfile()
            cachedProfile = profile
            
            if profile.accessLevels["premium"]?.isActive == true {
                return true
            }
        } catch {
            print("[SubscriptionService] Adapty profile fetch failed: \(error)")
            // Продовжуємо до StoreKit fallback
        }
        
        // 3. Fallback на StoreKit 2 (локальна перевірка)
        return await checkStoreKitSubscription()
    }
    
    // MARK: - StoreKit 2 Check
    
    private func checkStoreKitSubscription() async -> Bool {
        // Перевіряємо всі транзакції
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // Якщо є активна транзакція з підпискою — вважаємо premium
                if transaction.productType == .autoRenewable {
                    return true
                }
            case .unverified:
                continue
            }
        }
        return false
    }
}

// MARK: - ProfileApplicable (для Adapty)

extension SubscriptionService: ProfileApplicable {
    
    /// Оновлює кешований профіль після покупки через Adapty.
    func apply(profile: AdaptyProfile) {
        cachedProfile = profile
        
        let isPremium = profile.accessLevels["premium"]?.isActive == true
        print("[SubscriptionService] Profile applied. Premium: \(isPremium)")
    }
}
