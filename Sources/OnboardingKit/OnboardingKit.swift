// OnboardingKit.swift
// AppSceneKit SDK
//
// Головна точка входу OnboardingKit.
// Дзеркалить PaywallKit.swift — ті самі ідіоми, той самий configure/show pattern.

import UIKit

// MARK: - OnboardingKit

/// Головний клас OnboardingKit.
///
/// ```swift
/// // AppDelegate
/// OnboardingKit.configure(
///     configuration: .init(fetchTimeout: 10, displayTimeout: 15),
///     primaryProvider: AFAdaptyOnboardingProvider(
///         fetchTimeout: 10,    // ← має збігатись з configuration.fetchTimeout
///         displayTimeout: 15   // ← має збігатись з configuration.displayTimeout
///     ),
///     fallbackUI: MyOnboardingViewController.self
/// )
///
/// // Де завгодно
/// let result = await OnboardingKit.shared.show(placementId: "main", from: self)
/// ```
///
/// > **Важливо щодо таймаутів:**
/// > `OnboardingKitConfiguration.fetchTimeout` / `displayTimeout` використовуються
/// > для логування та документування наміру. Реальні таймаути контролює провайдер
/// > (наприклад `AFAdaptyOnboardingProvider.init(fetchTimeout:displayTimeout:)`).
/// > Переконайся що значення збігаються — SDK не може передати їх автоматично,
/// > бо провайдер вже створений до виклику `configure()`.
@MainActor
public final class OnboardingKit {

    // MARK: - Singleton

    public static let shared = OnboardingKit()
    private init() {}

    // MARK: - State

    private var configuration: OnboardingKitConfiguration?
    private var primaryProvider: OnboardingProvider?
    private var fallbackProvider: OnboardingProvider?
    private var eventHandler: OnboardingEventHandler?
    private var logger: PaywallKitLogger = ConsoleLogger()

    // MARK: - Storage key для "чи пройшов онбординг"

    private let completionKey = "FlowKit.onboardingCompleted"

    /// `true` якщо юзер вже завершив онбординг (persisted у UserDefaults).
    public var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completionKey) }
        set { UserDefaults.standard.set(newValue, forKey: completionKey) }
    }

    // MARK: - Configure

    /// Базова конфігурація з кастомним fallback provider.
    public static func configure(
        configuration: OnboardingKitConfiguration = .init(),
        primaryProvider: OnboardingProvider,
        fallbackProvider: OnboardingProvider? = nil,
        eventHandler: OnboardingEventHandler? = nil
    ) {
        let kit = OnboardingKit.shared
        kit.configuration = configuration
        kit.primaryProvider = primaryProvider
        kit.fallbackProvider = fallbackProvider
        kit.eventHandler = eventHandler
        kit.logger = configuration.logger ?? ConsoleLogger()
        kit.log("Configured. Primary: \(type(of: primaryProvider))", level: .info)
    }

    /// Зручна конфігурація — передай свій клас як fallback UI.
    ///
    /// ```swift
    /// OnboardingKit.configure(
    ///     primaryProvider: AFAdaptyOnboardingProvider(),
    ///     fallbackUI: MyOnboardingViewController.self
    /// )
    /// ```
    public static func configure(
        configuration: OnboardingKitConfiguration = .init(),
        primaryProvider: OnboardingProvider,
        fallbackUI: (any OnboardingKitUI.Type)? = nil,
        eventHandler: OnboardingEventHandler? = nil
    ) {
        let fallback = fallbackUI.map { FallbackOnboardingProvider(uiType: $0) }
        configure(
            configuration: configuration,
            primaryProvider: primaryProvider,
            fallbackProvider: fallback,
            eventHandler: eventHandler
        )
    }

    // MARK: - Show

    /// Показує онбординг. Автоматично переходить на fallback при помилці primary.
    ///
    /// - Parameters:
    ///   - placementId: Ідентифікатор placement з Adapty дашборду.
    ///   - from: ViewController для презентації.
    ///   - force: Ігнорує `hasCompleted` і показує завжди. Для тестування.
    @discardableResult
    public func show(
        placementId: String,
        from presenter: UIViewController,
        force: Bool = false
    ) async -> OnboardingResult {
        guard isConfigured else {
            log("show() called before configure().", level: .error)
            return .failed(.notConfigured)
        }

        // FIX #1: `force` раніше був оголошений але ніколи не використовувався.
        // Якщо юзер вже пройшов онбординг і force == false — повертаємо .skipped
        // без показу будь-якого UI. Саме ця перевірка і є головною метою `hasCompleted`.
        guard force || !hasCompleted else {
            log("Already completed — skipping. Use force: true to override.", level: .debug)
            return .skipped
        }

        // Перевіряємо мережу — якщо нема, одразу fallback
        let cfg = configuration!
        let hasNetwork: Bool

        if cfg.skipNetworkCheck {
            hasNetwork = true
        } else {
            hasNetwork = await NetworkReachability.shared.isAvailable()
        }

        log("Network: \(hasNetwork ? "✓" : "✗"), placement: \(placementId)", level: .debug)

        let result: OnboardingResult

        if hasNetwork {
            result = await showWithPrimary(placementId: placementId, from: presenter)
        } else {
            log("No network — going directly to fallback.", level: .info)
            result = await showFallback(placementId: placementId, from: presenter)
        }

        // Персистуємо та нотифікуємо
        if result.isFinished {
            hasCompleted = true
        }

        handleResult(result, placementId: placementId)
        return result
    }

    // MARK: - Internal

    private func showWithPrimary(placementId: String, from presenter: UIViewController) async -> OnboardingResult {
        guard let provider = primaryProvider else { return .failed(.notConfigured) }

        let result = await provider.present(placementId: placementId, from: presenter)

        // Fallback тільки при технічній помилці — не при .completed/.skipped
        if case .failed = result {
            log("Primary failed — switching to fallback.", level: .warning)
            return await showFallback(placementId: placementId, from: presenter)
        }

        return result
    }

    private func showFallback(placementId: String, from presenter: UIViewController) async -> OnboardingResult {
        guard let provider = fallbackProvider else {
            log("No fallback provider registered.", level: .error)
            return .failed(.noFallbackUI)
        }
        return await provider.present(placementId: placementId, from: presenter)
    }

    private func handleResult(_ result: OnboardingResult, placementId: String) {
        switch result {
        case .completed:
            log("✅ Onboarding completed.", level: .info)
            eventHandler?.onOnboardingCompleted(placementId: placementId)
            // FIX #2: Notification тепер надсилається і для .completed, і для .skipped.
            // Коментар у Notification.Name казав "після .completed або .skipped",
            // але .skipped раніше нотифікацію не надсилав — слухачі ніколи не дізнавались.
            NotificationCenter.default.post(name: .onboardingKitCompleted, object: nil)

        case .skipped:
            log("↩️ Onboarding skipped.", level: .info)
            eventHandler?.onOnboardingSkipped(placementId: placementId)
            // FIX #2: додано — симетрично до .completed.
            NotificationCenter.default.post(name: .onboardingKitCompleted, object: nil)

        case .failed(let error):
            log("❌ \(error.localizedDescription)", level: .error)
            eventHandler?.onOnboardingFailed(error: error, placementId: placementId)
        }
    }

    // MARK: - Helpers

    private var isConfigured: Bool {
        configuration != nil && primaryProvider != nil
    }

    private func log(_ message: String, level: PaywallKitLogLevel) {
        logger.log("[OnboardingKit] \(message)", level: level)
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Надсилається після .completed або .skipped.
    /// Слухай цю нотифікацію щоб дізнатись що онбординг завершено в будь-якому сценарії.
    ///
    /// ```swift
    /// NotificationCenter.default.addObserver(
    ///     forName: .onboardingKitCompleted,
    ///     object: nil,
    ///     queue: .main
    /// ) { _ in
    ///     // Переходимо на головний екран
    /// }
    /// ```
    static let onboardingKitCompleted = Notification.Name("OnboardingKit.completed")
}
