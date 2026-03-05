// NetworkReachability.swift
// AppSceneKit SDK
//
// Shared network monitor — використовується і OnboardingKit, і PaywallKit.
// Замінює: NWPathMonitor який створювався щоразу в OnboardingService.isNetworkAvailable().

import Network
import Foundation

// MARK: - NetworkReachability

/// Singleton для перевірки доступності мережі.
///
/// **Проблема яку вирішує:**
/// Оригінальний код створював новий `NWPathMonitor` при кожному виклику `isNetworkAvailable()`.
/// Це дорого — monitor починає з невідомого стану і робить перший callback з затримкою.
///
/// **Рішення:**
/// Один monitor живе весь час. Перший `await isAvailable()` чекає на перший callback.
/// Наступні — повертають закешований стан миттєво.
@MainActor
public final class NetworkReachability {

    public static let shared = NetworkReachability()
    private init() { startMonitoring() }

    // MARK: - State

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "FlowKit.NetworkReachability", qos: .utility)

    /// `nil` = перший callback ще не прийшов.
    private var currentStatus: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    // MARK: - Public API

    /// Повертає `true` якщо мережа доступна.
    /// Перший виклик чекає на callback від NWPathMonitor (~50ms).
    /// Наступні — повертають закешований стан миттєво.
    public func isAvailable() async -> Bool {
        if let status = currentStatus { return status }

        // Перший виклик — чекаємо на pathUpdateHandler
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    // MARK: - Private

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleUpdate(isAvailable)
            }
        }
        monitor.start(queue: queue)
    }

    private func handleUpdate(_ isAvailable: Bool) {
        currentStatus = isAvailable

        // Розбуджуємо всіх хто чекав на перший статус
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: isAvailable) }
    }

    deinit {
        monitor.cancel()
    }
}
