// AFAdaptyOnboardingProvider.swift
// AppSceneKit SDK
//
// Реалізація OnboardingProvider для Adapty Onboarding SDK.
// Вирішує всі проблеми AdaptyOnboardingViewController + OnboardingService.

import UIKit
import Adapty
import AdaptyUI

// MARK: - AFAdaptyOnboardingProvider

/// Провайдер онбордингу на базі Adapty.
/// Конформить до `OnboardingProvider` — повністю замінний.
///
/// **Що вирішує порівняно з оригіналом:**
/// - Замість 4 bool-прапорів — `OnboardingState` enum
/// - Timeout логіка інкапсульована в `AdaptyOnboardingDelegateHandler`
/// - "Alive signal" (octopusbuilder bug fix) в delegate, не у VC
/// - Permission requests через `OnboardingPermissionHandler` протокол
/// - Shared `NetworkReachability` замість нового monitor щоразу
public final class AFAdaptyOnboardingProvider: OnboardingProvider {

    // MARK: - Dependencies

    private let fetchTimeout: TimeInterval
    private let displayTimeout: TimeInterval
    private let permissionHandler: OnboardingPermissionHandler?

    // MARK: - Init

    public init(
        fetchTimeout: TimeInterval = 10.0,
        displayTimeout: TimeInterval = 15.0,
        permissionHandler: OnboardingPermissionHandler? = nil
    ) {
        self.fetchTimeout = fetchTimeout
        self.displayTimeout = displayTimeout
        self.permissionHandler = permissionHandler
    }

    // MARK: - OnboardingProvider

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> OnboardingResult {
        do {
            // 1. Fetch
            let onboarding = try await withTimeout(fetchTimeout) {
                try await Adapty.getOnboarding(placementId: placementId)
            }

            // 2. Configuration
            let configuration = try AdaptyUI.getOnboardingConfiguration(forOnboarding: onboarding)

            // 3. Show controller via continuation
            return await showController(configuration: configuration, from: presenter)

        } catch let error as OnboardingKitError {
            return .failed(error)
        } catch {
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    @MainActor
    private func showController(
        configuration: AdaptyUI.OnboardingConfiguration,
        from presenter: UIViewController
    ) async -> OnboardingResult {
        await withCheckedContinuation { continuation in
            let sink = SingleFireContinuation(continuation)
            let delegate = AdaptyOnboardingDelegateHandler(
                completion: sink,
                displayTimeout: displayTimeout,
                permissionHandler: permissionHandler
            )

            do {
                let controller = try AdaptyUI.onboardingController(
                    with: configuration,
                    delegate: delegate
                )
                controller.modalPresentationStyle = .fullScreen
                delegate.retain(on: controller)

                presenter.present(controller, animated: true) {
                    // Таймаут стартує тільки після того як controller реально показаний
                    delegate.beginDisplayTimeout()
                }
            } catch {
                sink.resume(with: .failed(.providerError(error)))
            }
        }
    }

    // MARK: - Timeout

    private func withTimeout<T>(
        _ seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw OnboardingKitError.fetchTimeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

// MARK: - AdaptyOnboardingDelegateHandler

/// Отримує події від AdaptyUI і конвертує їх у `OnboardingResult`.
///
/// **Ключові відмінності від оригіналу:**
/// 1. `SingleFireContinuation` замість `isCompleted` bool
/// 2. State machine замість окремих прапорів
/// 3. "Alive signal" логіка інкапсульована тут
/// 4. `beginDisplayTimeout()` викликається після реального показу controller
private final class AdaptyOnboardingDelegateHandler: NSObject, AdaptyOnboardingControllerDelegate {

    // MARK: - State

    /// Замінює 4 bool-прапори з оригінального коду.
    private enum State {
        case waitingForLoad     // Controller показаний, чекаємо didFinishLoading або alive signal
        case alive              // Контент живий — таймаут скасовано
        case done               // Continuation вже викликано
    }

    private var state: State = .waitingForLoad

    // MARK: - Dependencies

    private let completion: SingleFireContinuation<OnboardingResult>
    private let displayTimeout: TimeInterval
    private weak var permissionHandler: OnboardingPermissionHandler?

    // MARK: - Timeout

    private var displayTimeoutTask: Task<Void, Never>?

    // MARK: - Init

    init(
        completion: SingleFireContinuation<OnboardingResult>,
        displayTimeout: TimeInterval,
        permissionHandler: OnboardingPermissionHandler?
    ) {
        self.completion = completion
        self.displayTimeout = displayTimeout
        self.permissionHandler = permissionHandler
    }

    // MARK: - Lifetime

    func retain(on controller: UIViewController) {
        objc_setAssociatedObject(
            controller,
            &AdaptyOnboardingDelegateHandler.retainKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    private static var retainKey: UInt8 = 0

    // MARK: - Display timeout

    /// Викликається після `present(_:animated:completion:)` — тобто коли controller реально видно.
    /// Оригінальний код стартував таймаут до показу, що давало неточні результати.
    func beginDisplayTimeout() {
        guard case .waitingForLoad = state else { return }

        displayTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.displayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard case .waitingForLoad = self.state else { return }

            // Таймаут спрацював — onboarding ніколи не завантажився
            // Завершуємо як failed щоб OnboardingKit міг показати fallback
            self.finish(controller: nil, with: .failed(.displayTimeout))
        }
    }

    private func cancelDisplayTimeout() {
        displayTimeoutTask?.cancel()
        displayTimeoutTask = nil
    }

    // MARK: - "Alive signal" (octopusbuilder bug fix)
    //
    // Adapty onboarding може ніколи не надіслати `didFinishLoading`
    // через баг "Unable to hide query parameters from script (missing data)".
    // Але якщо приходять analytics або state events — контент явно живий і видимий.
    // Тому будь-який з них скасовує display timeout.

    private func handleAliveSignal() {
        guard case .waitingForLoad = state else { return }
        state = .alive
        cancelDisplayTimeout()
    }

    // MARK: - Completion

    private func finish(controller: AdaptyOnboardingController?, with result: OnboardingResult) {
        guard case .done = state else {
            state = .done
            cancelDisplayTimeout()

            guard let controller else {
                completion.resume(with: result)
                return
            }
            controller.dismiss(animated: true) {
                self.completion.resume(with: result)
            }
            return
        }
    }

    // MARK: - AdaptyOnboardingControllerDelegate

    // ── Loading ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        didFinishLoading action: OnboardingsDidFinishLoadingAction
    ) {
        handleAliveSignal()  // didFinishLoading — найнадійніший alive signal
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onAnalyticsEvent event: AdaptyOnboardingsAnalyticsEvent
    ) {
        // Analytics events приходять із web content → контент явно живий
        handleAliveSignal()
    }

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onStateUpdatedAction action: AdaptyOnboardingsStateUpdatedAction
    ) {
        // State updates також підтверджують що контент працює
        handleAliveSignal()
    }

    // ── Close ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onCloseAction action: AdaptyOnboardingsCloseAction
    ) {
        finish(controller: controller, with: .completed)
    }

    // ── Error ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        didFailWithError error: AdaptyUIError
    ) {
        finish(controller: controller, with: .failed(.providerError(error)))
    }

    // ── Custom actions (permissions) ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onCustomAction action: AdaptyOnboardingsCustomAction
    ) {
        let permAction = OnboardingPermissionAction(actionId: action.actionId)
        permissionHandler?.handlePermission(permAction)
    }

    // ── Paywall from onboarding ──

    func onboardingController(
        _ controller: AdaptyOnboardingController,
        onPaywallAction action: AdaptyOnboardingsOpenPaywallAction
    ) {
        // Adapty SDK відкриває paywall автоматично.
        // Якщо потрібна кастомна логіка — розширюй через OnboardingEventHandler.
    }
}
