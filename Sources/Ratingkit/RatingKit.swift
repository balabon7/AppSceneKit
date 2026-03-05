// RatingKit.swift
// AppSceneKit
//
// Розумний запит рейтингу з pre-prompt.
// Захищає квоту Apple (3 рази/рік) від незадоволених юзерів.

import UIKit
import StoreKit
import PaywallKit

// MARK: - RatingKit

/// Запитує рейтинг через кастомний pre-prompt.
///
/// **Flow:**
/// ```
/// requestIfNeeded() → pre-prompt "Подобається?"
///     ├── Так → SKStoreReviewController.requestReview()
///     └── Ні  → feedback URL або тихий dismiss
/// ```
///
/// **Використання:**
/// ```swift
/// // AppDelegate
/// RatingKit.configure(
///     configuration: .init(
///         appName: "PDF Editor",
///         minDaysBetweenPrompts: 14,
///         negativeFeedbackURL: URL(string: "mailto:support@app.com")
///     )
/// )
///
/// // Після успішної дії юзера
/// RatingKit.shared.requestIfNeeded(from: self)
/// ```
@MainActor
public final class RatingKit {

    // MARK: - Singleton

    public static let shared = RatingKit()
    private init() {}

    // MARK: - State

    private var configuration: RatingKitConfiguration = .init()
    private var eventHandler: RatingEventHandler?
    private var logger: PaywallKitLogger = ConsoleLogger()

    // MARK: - Configure

    public static func configure(
        configuration: RatingKitConfiguration = .init(),
        eventHandler: RatingEventHandler? = nil
    ) {
        shared.configuration = configuration
        shared.eventHandler = eventHandler
        shared.logger = configuration.logger ?? ConsoleLogger()
        shared.log("Configured. appName: \(configuration.appName)", level: .info)
    }

    // MARK: - Public API

    /// Показує pre-prompt якщо throttle дозволяє.
    /// Нічого не робить якщо: показали нещодавно, вичерпали ліміт версії, або юзер вже оцінив.
    ///
    /// - Parameter presenter: ViewController для презентації.
    /// - Parameter force: Ігнорує throttle. Для тестування.
    @discardableResult
    public func requestIfNeeded(
        from presenter: UIViewController,
        force: Bool = false
    ) async -> RatingResult {
        guard force || shouldShowPrompt() else {
            log("Throttled — skipping prompt.", level: .debug)
            return .throttled
        }

        return await showPrompt(from: presenter)
    }

    /// Скидає всю статистику. Для тестування.
    public func resetState() {
        storage.reset()
        log("State reset.", level: .debug)
    }

    // MARK: - Throttle

    private func shouldShowPrompt() -> Bool {
        // 1. Юзер вже натиснув "Подобається" і ми вже показали Apple prompt
        if storage.hasRatedThisVersion { return false }

        // 2. Ліміт показів на поточну версію
        let currentVersion = appVersion
        let count = storage.promptCount(for: currentVersion)
        guard count < configuration.maxPromptsPerVersion else {
            log("Max prompts (\(configuration.maxPromptsPerVersion)) reached for v\(currentVersion).", level: .debug)
            return false
        }

        // 3. Мінімальний інтервал між показами
        if let lastDate = storage.lastPromptDate {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysSince >= configuration.minDaysBetweenPrompts else {
                log("Only \(daysSince) days since last prompt (min: \(configuration.minDaysBetweenPrompts)).", level: .debug)
                return false
            }
        }

        return true
    }

    // MARK: - Show

    private func showPrompt(from presenter: UIViewController) async -> RatingResult {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<RatingResult, Never>) in
            let sink = SingleFireContinuation(continuation)
            let vc = RatingPromptViewController(
                configuration: configuration,
                onResult: { sink.resume(with: $0) }
            )
            vc.modalPresentationStyle = .overFullScreen
            vc.modalTransitionStyle = .crossDissolve
            presenter.present(vc, animated: true)
        }

        handleResult(result)
        return result
    }

    // MARK: - Handle result

    private func handleResult(_ result: RatingResult) {
        let version = appVersion

        switch result {
        case .positive:
            log("✅ User is happy — requesting Apple review.", level: .info)
            storage.setHasRated(for: version)
            storage.incrementPromptCount(for: version)
            storage.lastPromptDate = Date()
            requestAppleReview()
            eventHandler?.onPositiveFeedback()

        case .negative:
            log("👎 User is unhappy — opening feedback URL.", level: .info)
            storage.incrementPromptCount(for: version)
            storage.lastPromptDate = Date()
            if let url = configuration.negativeFeedbackURL {
                UIApplication.shared.open(url)
            }
            eventHandler?.onNegativeFeedback()

        case .dismissed:
            log("↩️ Prompt dismissed.", level: .debug)
            storage.incrementPromptCount(for: version)
            storage.lastPromptDate = Date()
            eventHandler?.onDismissed()

        case .throttled:
            break
        }
    }

    // MARK: - Apple Review

    private func requestAppleReview() {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            if #available(iOS 16.0, *) {
                AppStore.requestReview(in: scene)
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func log(_ message: String, level: PaywallKitLogLevel) {
        logger.log("[RatingKit] \(message)", level: level)
    }

    // MARK: - Storage

    private let storage = RatingStorage()
}

// MARK: - RatingKitConfiguration

public struct RatingKitConfiguration: Sendable {

    /// Назва додатку — відображається у pre-prompt.
    public let appName: String

    /// Мінімум днів між показами pre-prompt. Default: 30.
    public let minDaysBetweenPrompts: Int

    /// Максимум показів на одну версію додатку. Default: 2.
    /// Захищає від нав'язливості якщо юзер постійно відхиляє.
    public let maxPromptsPerVersion: Int

    /// URL для незадоволених юзерів. Наприклад: mailto:support@app.com
    /// Якщо `nil` — просто dismiss без дії.
    public let negativeFeedbackURL: URL?

    /// Логгер — той самий що в PaywallKit.
    public let logger: PaywallKitLogger?

    public init(
        appName: String = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
        minDaysBetweenPrompts: Int = 30,
        maxPromptsPerVersion: Int = 2,
        negativeFeedbackURL: URL? = nil,
        logger: PaywallKitLogger? = nil
    ) {
        self.appName = appName
        self.minDaysBetweenPrompts = minDaysBetweenPrompts
        self.maxPromptsPerVersion = maxPromptsPerVersion
        self.negativeFeedbackURL = negativeFeedbackURL
        self.logger = logger
    }
}

// MARK: - RatingResult

public enum RatingResult: Sendable {
    case positive    // Юзер задоволений → Apple prompt показано
    case negative    // Юзер незадоволений → feedback URL відкрито (або dismiss)
    case dismissed   // Юзер закрив без відповіді
    case throttled   // Throttle — prompt не показувався
}

// MARK: - RatingEventHandler

public protocol RatingEventHandler: AnyObject {
    func onPositiveFeedback()
    func onNegativeFeedback()
    func onDismissed()
}

public extension RatingEventHandler {
    func onPositiveFeedback() {}
    func onNegativeFeedback() {}
    func onDismissed()        {}
}

// MARK: - RatingStorage (internal)

private final class RatingStorage {

    private enum Keys {
        static let lastPromptDate     = "RatingKit.lastPromptDate"
        static let promptCounts       = "RatingKit.promptCounts"       // [String: Int]
        static let ratedVersions      = "RatingKit.ratedVersions"      // [String]
    }

    private let defaults = UserDefaults.standard

    var lastPromptDate: Date? {
        get { defaults.object(forKey: Keys.lastPromptDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastPromptDate) }
    }

    func promptCount(for version: String) -> Int {
        let counts = defaults.dictionary(forKey: Keys.promptCounts) as? [String: Int] ?? [:]
        return counts[version] ?? 0
    }

    func incrementPromptCount(for version: String) {
        var counts = defaults.dictionary(forKey: Keys.promptCounts) as? [String: Int] ?? [:]
        counts[version, default: 0] += 1
        defaults.set(counts, forKey: Keys.promptCounts)
    }

    var hasRatedThisVersion: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let rated = defaults.stringArray(forKey: Keys.ratedVersions) ?? []
        return rated.contains(version)
    }

    func setHasRated(for version: String) {
        var rated = defaults.stringArray(forKey: Keys.ratedVersions) ?? []
        if !rated.contains(version) { rated.append(version) }
        defaults.set(rated, forKey: Keys.ratedVersions)
    }

    func reset() {
        [Keys.lastPromptDate, Keys.promptCounts, Keys.ratedVersions]
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
