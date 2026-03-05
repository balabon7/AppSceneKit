// OnboardingKitUI.swift
// AppSceneKit SDK
//
// Протокол для підключення власного онбординг UI.
// Дзеркалить PaywallKitUI.swift — ті самі ідіоми.

import UIKit

// MARK: - OnboardingKitUI

/// Реалізуй цей протокол на своєму `UIViewController` щоб підключити його як fallback онбординг.
///
/// ```swift
/// final class MyOnboardingVC: UIViewController, OnboardingKitUI {
///
///     private var context: OnboardingUIContext!
///
///     static func make(context: OnboardingUIContext) -> UIViewController {
///         let vc = MyOnboardingVC()
///         vc.context = context
///         return vc
///     }
///
///     // Юзер натиснув "Continue" на останньому кроці
///     @objc func doneTapped()   { context.complete() }
///
///     // Юзер натиснув "Skip"
///     @objc func skipTapped()   { context.skip() }
/// }
/// ```
public protocol OnboardingKitUI: UIViewController {
    @MainActor
    static func make(context: OnboardingUIContext) -> UIViewController
}

// MARK: - OnboardingUIContext

/// Всі дані та дії які SDK передає у твій ViewController.
@MainActor
public final class OnboardingUIContext {

    // MARK: - Data

    /// Ідентифікатор placement (для логування/аналітики).
    public let placementId: String

    // MARK: - Actions

    /// Виклич коли юзер завершив всі кроки онбордингу.
    public let complete: () -> Void

    /// Виклич коли юзер натиснув Skip.
    public let skip: () -> Void

    // MARK: - Init (SDK internal)

    internal init(
        placementId: String,
        complete: @escaping () -> Void,
        skip: @escaping () -> Void
    ) {
        self.placementId = placementId
        self.complete = complete
        self.skip = skip
    }
}

// MARK: - FallbackOnboardingProvider

/// Провайдер що показує твій кастомний OnboardingKitUI ViewController.
/// Використовується як fallback коли Adapty недоступний.
public final class FallbackOnboardingProvider: OnboardingProvider {

    private let uiType: any OnboardingKitUI.Type

    public init(uiType: any OnboardingKitUI.Type) {
        self.uiType = uiType
    }

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> OnboardingResult {
        await withCheckedContinuation { continuation in
            let sink = SingleFireContinuation(continuation)

            let context = OnboardingUIContext(
                placementId: placementId,
                complete: { sink.resume(with: .completed) },
                skip:    { sink.resume(with: .skipped) }
            )

            let controller = uiType.make(context: context)
            controller.modalPresentationStyle = .fullScreen

            // Прив'язуємо context (і sink) до controller
            objc_setAssociatedObject(
                controller,
                &FallbackOnboardingProvider.contextKey,
                context,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            presenter.present(controller, animated: true)
        }
    }

    private static var contextKey: UInt8 = 0
}
