// OnboardingProvider.swift
// AppSceneKit SDK
//
// Протокол провайдера онбордингу. Дзеркалить PaywallProvider.swift.

import UIKit

// MARK: - OnboardingProvider

/// Абстракція провайдера онбордингу.
/// Реалізуй щоб підключити Adapty, власний сервер, або static screens.
public protocol OnboardingProvider: AnyObject, Sendable {

    /// Показує онбординг.
    /// - Returns: `OnboardingResult` після завершення.
    @MainActor
    func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> OnboardingResult
}

// MARK: - OnboardingEventHandler

/// Протокол для обробки подій онбордингу (аналітика).
public protocol OnboardingEventHandler: AnyObject {

    @MainActor
    func onOnboardingCompleted(placementId: String)

    @MainActor
    func onOnboardingSkipped(placementId: String)

    @MainActor
    func onOnboardingFailed(error: OnboardingKitError, placementId: String)
}

// Default no-op implementations
public extension OnboardingEventHandler {
    func onOnboardingCompleted(placementId: String) {}
    func onOnboardingSkipped(placementId: String) {}
    func onOnboardingFailed(error: OnboardingKitError, placementId: String) {}
}
