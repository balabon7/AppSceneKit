// AppFlowKit.swift
// AppSceneKit SDK
//
// Координатор першого запуску: onboarding → paywall → home.
// Замінює логіку з CustomNavigationController.runFirstLaunchFlow().
//
// ─────────────────────────────────────────────────────────────────
// ПРОБЛЕМА в оригіналі:
//   CustomNavigationController знав про OnboardingService, PaywallService,
//   порядок показу, та навіть про hasCompletedOnboarding — SRP порушено повністю.
//
// РІШЕННЯ:
//   AppFlowKit — окремий координатор. NavigationController тільки питає:
//   "з чого починати?" і викликає flow.run(). Більше нічого.
// ─────────────────────────────────────────────────────────────────

import UIKit

// MARK: - AppFlowKit

/// Координатор першого запуску.
///
/// **Використання в NavigationController:**
/// ```swift
/// override func viewDidLoad() {
///     super.viewDidLoad()
///
///     if OnboardingKit.shared.hasCompleted {
///         goToHome()
///         if showPaywallOnLaunch {
///             Task { await PaywallKit.shared.show(placementId: "launch", from: topVC) }
///         }
///     } else {
///         Task {
///             let result = await AppFlowKit.shared.runFirstLaunch(from: placeholderVC)
///             goToHome()
///         }
///     }
/// }
/// ```
@MainActor
public final class AppFlowKit {

    public static let shared = AppFlowKit()
    private init() {}

    // MARK: - Configuration

    private var onboardingPlacementId: String = ""
    private var paywallPlacementId: String = ""
    private var showPaywallAfterOnboarding: Bool = true

    /// Конфігурує координатор.
    ///
    /// ```swift
    /// AppFlowKit.configure(
    ///     onboardingPlacementId: "onboarding_main",
    ///     paywallPlacementId: "paywall_after_onboarding",
    ///     showPaywallAfterOnboarding: true
    /// )
    /// ```
    public static func configure(
        onboardingPlacementId: String,
        paywallPlacementId: String,
        showPaywallAfterOnboarding: Bool = true
    ) {
        shared.onboardingPlacementId = onboardingPlacementId
        shared.paywallPlacementId = paywallPlacementId
        shared.showPaywallAfterOnboarding = showPaywallAfterOnboarding
    }

    // MARK: - First Launch Flow

    /// Запускає повний флоу першого запуску.
    ///
    /// Послідовність:
    /// 1. OnboardingKit.show() — якщо завершено/пропущено → крок 2
    /// 2. PaywallKit.show() — якщо увімкнений
    ///
    /// Повертає після того як обидва кроки завершено.
    /// Незалежно від результатів — флоу завжди завершується.
    ///
    /// ```swift
    /// Task {
    ///     await AppFlowKit.shared.runFirstLaunch(from: placeholderVC)
    ///     goToHome()   // ← викликаєш сам після повернення
    /// }
    /// ```
    @discardableResult
    public func runFirstLaunch(from presenter: UIViewController) async -> AppFlowResult {

        // ── Step 1: Onboarding ──
        let onboardingResult = await OnboardingKit.shared.show(
            placementId: onboardingPlacementId,
            from: presenter
        )

        log("Onboarding: \(onboardingResult)")

        // ── Step 2: Paywall (тільки якщо увімкнений) ──
        guard showPaywallAfterOnboarding else {
            return AppFlowResult(onboarding: onboardingResult, paywall: nil)
        }

        // Показуємо paywall з forceShow: true після онбордингу
        // Це дозволяє користувачу відновити покупку якщо вона вже є
        let paywallResult = await PaywallKit.shared.show(
            placementId: paywallPlacementId,
            from: presenter,
            forceShow: true  // Показати навіть якщо є підписка (для відновлення)
        )

        log("Paywall: \(paywallResult)")

        return AppFlowResult(onboarding: onboardingResult, paywall: paywallResult)
    }

    // MARK: - Returning User Paywall

    /// Показує paywall для юзера що вже пройшов онбординг (наприклад при кожному запуску).
    ///
    /// ```swift
    /// // В NavigationController, якщо showPaywallOnLaunch == true
    /// await AppFlowKit.shared.showReturningUserPaywall(
    ///     placementId: "paywall_launch",
    ///     from: topVC
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - placementId: ID placement з Adapty
    ///   - presenter: UIViewController з якого показати paywall
    ///   - forceShow: Якщо `true`, показує paywall навіть якщо є підписка (для відновлення/налаштувань). За замовчуванням `false`.
    @discardableResult
    public func showReturningUserPaywall(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false
    ) async -> PaywallResult {
        await PaywallKit.shared.show(placementId: placementId, from: presenter, forceShow: forceShow)
    }

    // MARK: - Helper

    private func log(_ message: String) {
        print("[AppFlowKit] \(message)")
    }
}

// MARK: - AppFlowResult

/// Результат повного флоу першого запуску.
public struct AppFlowResult {
    public let onboarding: OnboardingResult
    public let paywall: PaywallResult?

    /// `true` якщо юзер купив або відновив підписку під час флоу.
    public var isSubscribed: Bool {
        paywall?.isSuccess ?? false
    }
}
