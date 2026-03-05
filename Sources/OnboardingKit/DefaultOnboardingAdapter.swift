// DefaultOnboardingAdapter.swift
// AppSceneKit SDK
//
// Адаптер для існуючого OnboardingViewController щоб він працював з OnboardingKit.

import UIKit

/// Адаптер що обгортає ваш існуючий OnboardingViewController
/// і робить його сумісним з OnboardingKitUI протоколом.
final class DefaultOnboardingAdapter: UIViewController, OnboardingKitUI {
    
    private var context: OnboardingUIContext!
    
    // MARK: - OnboardingKitUI
    
    static func make(context: OnboardingUIContext) -> UIViewController {
        let adapter = DefaultOnboardingAdapter()
        adapter.context = context
        return adapter
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Створюємо оригінальний OnboardingViewController
        let onboardingVC = OnboardingViewController()
        onboardingVC.onCompletion = { [weak self] in
            // Коли юзер завершує онбординг — повідомляємо SDK
            self?.context.complete()
        }
        
        // Вбудовуємо як child controller
        addChild(onboardingVC)
        view.addSubview(onboardingVC.view)
        onboardingVC.view.frame = view.bounds
        onboardingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        onboardingVC.didMove(toParent: self)
    }
}
