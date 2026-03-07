//
//  UserPreferences.swift
//  DocScanPro
//
//  Created on 04.03.2026.
//

import Foundation

/// Manager for user preferences and app state
final class UserPreferences {
    
    static let shared = UserPreferences()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Keys
    
    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastPaywallShownDate = "lastPaywallShownDate"
        static let isPremiumUser = "isPremiumUser"
        static let paywallVariant = "paywallVariant"
    }
    
    // MARK: - Paywall Variant
    
    enum PaywallVariant: String {
        case standard = "standard"
        case adapty = "adapty"
    }
    
    // MARK: - Properties
    
    /// Whether user has completed onboarding
    var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { userDefaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }
    
    /// Last date when paywall was shown
    var lastPaywallShownDate: Date? {
        get { userDefaults.object(forKey: Keys.lastPaywallShownDate) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.lastPaywallShownDate) }
    }
    
    /// Whether user has premium subscription
    var isPremiumUser: Bool {
        get { userDefaults.bool(forKey: Keys.isPremiumUser) }
        set { userDefaults.set(newValue, forKey: Keys.isPremiumUser) }
    }
    
    /// Current paywall variant (for A/B testing)
    var paywallVariant: PaywallVariant {
        get {
            if let rawValue = userDefaults.string(forKey: Keys.paywallVariant),
               let variant = PaywallVariant(rawValue: rawValue) {
                return variant
            }
            // Default: randomly assign variant on first access
            let variant: PaywallVariant = Bool.random() ? .standard : .adapty
            userDefaults.set(variant.rawValue, forKey: Keys.paywallVariant)
            return variant
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.paywallVariant)
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Methods
    
    /// Check if should show paywall on launch
    func shouldShowPaywallOnLaunch() -> Bool {
        // Don't show if user is premium
        guard !isPremiumUser else { 
            print("[UserPreferences] Not showing paywall: user is premium")
            return false 
        }
        
        // Don't show during onboarding - використовуємо OnboardingKit як джерело правди
        let onboardingCompleted = OnboardingKit.shared.hasCompleted
        guard onboardingCompleted else { 
            print("[UserPreferences] Not showing paywall: onboarding not completed")
            return false 
        }
        
        print("[UserPreferences] Should show paywall: all conditions met")
        // Show paywall on every app launch for non-premium users
        return true
    }
    
    /// Mark paywall as shown
    func markPaywallShown() {
        lastPaywallShownDate = Date()
    }
    
    /// Reset all preferences (useful for testing)
    func reset() {
        userDefaults.removeObject(forKey: Keys.hasCompletedOnboarding)
        userDefaults.removeObject(forKey: Keys.lastPaywallShownDate)
        userDefaults.removeObject(forKey: Keys.isPremiumUser)
        userDefaults.removeObject(forKey: Keys.paywallVariant)
    }
}
