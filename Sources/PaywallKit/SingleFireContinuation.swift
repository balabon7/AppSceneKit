// SingleFireContinuation.swift
// PaywallKit SDK
//
// Потокобезпечний wrapper навколо CheckedContinuation.
// Гарантує що continuation викликається рівно один раз — незалежно від race conditions.

import Foundation

// MARK: - SingleFireContinuation

/// `CheckedContinuation` може бути викликаний лише один раз.
/// Цей клас захищає від подвійного виклику через `@MainActor` + `isConsumed` guard.
///
/// **Проблема яку вирішує:**
/// У delegate-based API кілька callbacks можуть спрацювати одночасно
/// (наприклад `didFinishPurchase` і `didFailPurchase`).
/// Без захисту — crash або undefined behavior.
@MainActor
final class SingleFireContinuation<T> {

    private var continuation: CheckedContinuation<T, Never>?
    nonisolated(unsafe) private var isConsumed = false

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    /// Передає результат у continuation. Повторні виклики ігноруються.
    func resume(with value: T) {
        guard !isConsumed else { return }
        isConsumed = true
        continuation?.resume(returning: value)
        continuation = nil // Звільняємо пам'ять одразу
    }

    deinit {
        // Якщо continuation не було викликано — це означає що UIKit тихо провалив
        // presenter.present() (наприклад presenter not in window hierarchy) і жоден
        // delegate-колбек не прийшов. PaywallKit тепер перевіряє presenter.view.window
        // перед show, тому цього не має траплятись. Але якщо все ж трапилось —
        // логуємо замість краша: resume вже неможливий з deinit (потрібен @MainActor).
        if !isConsumed {
            print("[PaywallKit][warning] SingleFireContinuation deallocated without being consumed. " +
                  "Presenter was likely not in window hierarchy. Check logs above for details.")
        }
    }
}
