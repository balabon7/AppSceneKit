// DefaultOnboardingAdapter.swift
// AppSceneKit SDK
//
// Адаптер для існуючого OnboardingViewController щоб він працював з OnboardingKit.

import UIKit

/// Адаптер що обгортає `OnboardingViewController` і робить його сумісним з `OnboardingKitUI`.
///
/// SDK використовує цей адаптер автоматично коли ти передаєш `fallbackUI: DefaultOnboardingAdapter.self`.
/// Прямо створювати `DefaultOnboardingAdapter()` не потрібно — завжди через `make(context:)`.
final class DefaultOnboardingAdapter: UIViewController, OnboardingKitUI {

    // MARK: - Properties

    // FIX #1: force-unwrap замінено на опціонал з guard.
    // Якщо хтось створить DefaultOnboardingAdapter() напряму (не через make),
    // context буде nil — guard у viewDidLoad захистить від crash.
    private var context: OnboardingUIContext?

    // MARK: - OnboardingKitUI

    // FIX #2: Додано @MainActor — вимагається протоколом OnboardingKitUI.
    // Без нього Swift 6 strict concurrency видає compile error.
    @MainActor
    static func make(context: OnboardingUIContext) -> UIViewController {
        let adapter = DefaultOnboardingAdapter()
        adapter.context = context
        return adapter
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // FIX #1: guard замість force-unwrap на context.
        // Якщо адаптер створено не через make(context:) — логуємо і нічого не показуємо,
        // замість crash при звертанні до context.complete().
        guard let context else {
            assertionFailure("[DefaultOnboardingAdapter] context is nil. Always create via make(context:).")
            return
        }

        // Створюємо OnboardingViewController і прив'язуємо до SDK через onCompletion.
        let onboardingVC = OnboardingViewController()
        onboardingVC.onCompletion = { [weak self] in
            // Юзер натиснув Continue на останній сторінці або Skip —
            // повідомляємо SDK що онбординг завершено.
            // [weak self] щоб не утримувати адаптер після dismiss.
            self?.context?.complete()
        }

        // Вбудовуємо як child controller — правильний патерн для containment.
        addChild(onboardingVC)
        view.addSubview(onboardingVC.view)
        onboardingVC.view.frame = view.bounds
        onboardingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        onboardingVC.didMove(toParent: self)
    }
}
