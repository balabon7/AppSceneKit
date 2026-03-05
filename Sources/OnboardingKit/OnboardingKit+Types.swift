// OnboardingKit+Types.swift
// AppSceneKit SDK
//
// Типи для OnboardingKit. Дзеркалить PaywallKit+Types.swift.

import Foundation

// MARK: - OnboardingResult

/// Результат показу онбордингу.
public enum OnboardingResult: Sendable {
    case completed    // Юзер пройшов до кінця
    case skipped      // Юзер натиснув "Skip" — онбординг вважається пройденим
    case failed(OnboardingKitError)
}

extension OnboardingResult {
    /// `true` якщо онбординг завершено в будь-якому позитивному сценарії.
    public var isFinished: Bool {
        switch self {
        case .completed, .skipped: return true
        case .failed: return false
        }
    }
}

// MARK: - OnboardingKitError

public enum OnboardingKitError: LocalizedError, Sendable {
    case notConfigured
    case fetchTimeout
    case displayTimeout
    case noFallbackUI
    case providerError(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .notConfigured:   return "[OnboardingKit] SDK not configured. Call OnboardingKit.configure() first."
        case .fetchTimeout:    return "[OnboardingKit] Adapty fetch timed out."
        case .displayTimeout:  return "[OnboardingKit] Onboarding did not finish loading in time."
        case .noFallbackUI:    return "[OnboardingKit] Primary provider failed and no fallback UI registered."
        case .providerError(let e): return "[OnboardingKit] Provider error: \(e.localizedDescription)"
        case .unknown:         return "[OnboardingKit] Unknown error."
        }
    }
}

// MARK: - OnboardingKitConfiguration

/// Конфігурація OnboardingKit. Передається один раз при configure().
public struct OnboardingKitConfiguration: Sendable {

    /// Таймаут для завантаження онбордингу з сервера (fetch + конфігурація).
    public let fetchTimeout: TimeInterval

    /// Таймаут після показу controller — якщо `didFinishLoading` ніколи не прийде
    /// (octopusbuilder bug). SDK переходить на fallback або вважає онбординг завантаженим.
    public let displayTimeout: TimeInterval

    /// Пропускати перевірку мережі. Для тестування.
    public let skipNetworkCheck: Bool

    /// Логгер — той самий що в PaywallKit.
    public let logger: PaywallKitLogger?

    public init(
        fetchTimeout: TimeInterval = 10.0,
        displayTimeout: TimeInterval = 15.0,
        skipNetworkCheck: Bool = false,
        logger: PaywallKitLogger? = nil
    ) {
        self.fetchTimeout = fetchTimeout
        self.displayTimeout = displayTimeout
        self.skipNetworkCheck = skipNetworkCheck
        self.logger = logger
    }
}

// MARK: - OnboardingPermissionHandler

/// Протокол для обробки permission запитів з Adapty онбордингу.
///
/// Adapty онбординг може надсилати custom actions типу "request_notifications"
/// або "request_tracking". Замість того щоб обробляти їх в SDK або у ViewController,
/// ти реалізуєш цей протокол і реєструєш його в configure().
///
/// ```swift
/// final class MyPermissionHandler: OnboardingPermissionHandler {
///     func handlePermission(_ action: OnboardingPermissionAction) {
///         switch action {
///         case .notifications: requestNotifications()
///         case .tracking:      requestATT()
///         case .custom(let id): print("custom: \(id)")
///         }
///     }
/// }
/// ```
public protocol OnboardingPermissionHandler: AnyObject {
    @MainActor
    func handlePermission(_ action: OnboardingPermissionAction)
}

// MARK: - OnboardingPermissionAction

/// Тип permission action з Adapty custom action.
public enum OnboardingPermissionAction: Sendable {
    case notifications              // "request_notifications"
    case tracking                   // "request_tracking"
    case custom(id: String)         // Будь-який інший action id
}

extension OnboardingPermissionAction {
    /// Конвертує рядковий id з Adapty у типизований action.
    init(actionId: String) {
        switch actionId {
        case "request_notifications": self = .notifications
        case "request_tracking":      self = .tracking
        default:                      self = .custom(id: actionId)
        }
    }
}
