// PaywallKit+Types.swift
// PaywallKit SDK
//
// Public types: results, errors, configuration.

import Foundation
import UIKit

// MARK: - PaywallResult

/// Результат показу paywall.
public enum PaywallResult: Sendable {
    case purchased              // Щойно купили підписку
    case restored               // Відновили покупку
    case alreadyPurchased       // Вже є активна підписка (paywall не показувався)
    case cancelled              // Юзер закрив paywall без покупки
    case failed(PaywallKitError)
}

extension PaywallResult {
    /// `true` якщо юзер має активну підписку (купив, відновив або вже мав).
    public var isSuccess: Bool {
        switch self {
        case .purchased, .restored, .alreadyPurchased: return true
        default: return false
        }
    }
}

// MARK: - PaywallKitError

public enum PaywallKitError: LocalizedError, Sendable {
    // Configuration
    case notConfigured
    case noProductIds

    // Network / loading
    case timeout
    case noProducts

    // Purchase
    case subscriptionNotActive
    case noActiveSubscription
    case verificationFailed
    case providerError(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .notConfigured:         return "[PaywallKit] SDK not configured. Call PaywallKit.configure() first."
        case .noProductIds:          return "[PaywallKit] No product IDs provided in configuration."
        case .timeout:               return "[PaywallKit] Request timed out."
        case .noProducts:            return "[PaywallKit] No products available for purchase."
        case .subscriptionNotActive: return "[PaywallKit] Purchase completed but subscription is not active."
        case .noActiveSubscription:  return "[PaywallKit] No active subscription found."
        case .verificationFailed:    return "[PaywallKit] Transaction verification failed."
        case .providerError(let e):  return "[PaywallKit] Provider error: \(e.localizedDescription)"
        case .unknown:               return "[PaywallKit] Unknown error occurred."
        }
    }
}

// MARK: - PaywallKitConfiguration

/// Конфігурація SDK. Передається один раз при ініціалізації.
public struct PaywallKitConfiguration: Sendable {

    /// Product IDs для StoreKit fallback.
    public let productIds: [String]

    /// Таймаут для мережевих запитів провайдера.
    public let fetchTimeout: TimeInterval

    /// Акцентний колір для paywall UI (за замовчуванням .systemBlue).
    public let accentColor: UIColor

    /// Логгер. Замінить дефолтний `print`-based.
    public let logger: PaywallKitLogger?

    public init(
        productIds: [String],
        fetchTimeout: TimeInterval = 15.0,
        accentColor: UIColor = .systemBlue,
        logger: PaywallKitLogger? = nil
    ) {
        self.productIds = productIds
        self.fetchTimeout = fetchTimeout
        self.accentColor = accentColor
        self.logger = logger
    }
}

// MARK: - PaywallKitLogger

/// Протокол логгера. Підстав будь-який інструмент: OSLog, Firebase, власний.
public protocol PaywallKitLogger: Sendable {
    func log(_ message: String, level: PaywallKitLogLevel)
}

public enum PaywallKitLogLevel: Sendable {
    case debug, info, warning, error
}

/// Дефолтний логгер через `print`.
public struct ConsoleLogger: PaywallKitLogger {
    public init() {}
    public func log(_ message: String, level: PaywallKitLogLevel) {
        print("[PaywallKit][\(level)] \(message)")
    }
}
