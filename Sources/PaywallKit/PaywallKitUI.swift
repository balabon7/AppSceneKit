// PaywallKitUI.swift
// PaywallKit SDK
//
// Протокол для підключення власного paywall UI до SDK.
// Юзер реалізує цей протокол на своєму ViewController — SDK про решту знає сам.

import UIKit
import StoreKit

// MARK: - PaywallKitUI

/// Реалізуй цей протокол на своєму `UIViewController` щоб підключити його до PaywallKit.
///
/// **Мінімальна інтеграція — 3 кроки:**
/// ```swift
/// // 1. Конформність
/// final class MyPaywall: UIViewController, PaywallKitUI {
///
///     // 2. SDK передає продукти через ініціалізатор
///     static func make(context: PaywallUIContext) -> UIViewController {
///         return MyPaywall(context: context)
///     }
///
///     // 3. Коли юзер тапає кнопку — передаєш події через context
///     @IBAction func buyTapped() {
///         context.purchase(products[selectedIndex])
///     }
/// }
///
/// // 4. Реєстрація
/// PaywallKit.configure(..., customUI: MyPaywall.self)
/// ```
public protocol PaywallKitUI: UIViewController {

    /// SDK викликає це щоб створити твій контролер.
    /// Отримуєш `PaywallUIContext` з усіма даними та callbacks.
    @MainActor
    static func make(context: PaywallUIContext) -> UIViewController
}

// MARK: - PaywallUIContext

/// Всі дані та дії які SDK передає у твій ViewController.
/// Зберігай як `let context: PaywallUIContext` і використовуй де потрібно.
@MainActor
public final class PaywallUIContext {

    // MARK: - Data

    /// Відсортований список продуктів (від дешевого до дорогого).
    public let products: [PaywallProduct]

    /// Ідентифікатор placement звідки відкрили paywall.
    public let placementId: String

    /// Акцентний колір для paywall UI (за замовчуванням .systemBlue).
    public let accentColor: UIColor

    // MARK: - Actions

    /// Викликай коли юзер тапає "Buy" / "Subscribe".
    public let purchase: (PaywallProduct) -> Void

    /// Викликай коли юзер тапає "Restore".
    public let restore: () -> Void

    /// Викликай коли юзер тапає "Close" / "X".
    public let close: () -> Void

    // MARK: - State updates

    /// SDK передає стан покупки (loading / error / success).
    /// Підписуйся щоб оновити UI.
    public var onStateChange: ((PaywallUIState) -> Void)?

    // MARK: - Init (SDK internal)

    internal init(
        products: [PaywallProduct],
        placementId: String,
        accentColor: UIColor = .systemBlue,
        purchase: @escaping (PaywallProduct) -> Void,
        restore: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.products = products
        self.placementId = placementId
        self.accentColor = accentColor
        self.purchase = purchase
        self.restore = restore
        self.close = close
    }
}

// MARK: - PaywallProduct

/// Уніфікована обгортка продукту.
/// Незалежно від провайдера (Adapty або StoreKit) — отримуєш однаковий об'єкт.
public struct PaywallProduct: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let displayPrice: String           // "4.99 USD"
    public let pricePerMonth: String?         // "1.67 USD/mo" — для річних планів
    public let introductoryOffer: String?     // "3 days free"
    public let subscriptionPeriod: SubscriptionPeriod

    public var isPopular: Bool = false        // SDK виставляє автоматично для найпопулярнішого
}

// MARK: - SubscriptionPeriod

public enum SubscriptionPeriod: Sendable {
    case weekly, monthly, quarterly, yearly, lifetime, unknown
}

// MARK: - PaywallUIState

/// Стан який SDK передає у твій UI під час покупки.
public enum PaywallUIState: Sendable {
    case idle
    case loading                              // Показуй spinner
    case purchasing(productId: String)        // Конкретний продукт купується
    case restoring
    case success(PaywallResult)               // SDK вже закриє paywall сам
    case error(String)                        // Покажи alert / inline error
}

// MARK: - PaywallKit.configure overload

//public extension PaywallKit {
//
//    /// Реєструє твій кастомний UI для StoreKit fallback провайдера.
//    ///
//    /// **Використання:**
//    /// ```swift
//    /// PaywallKit.configure(
//    ///     configuration: config,
//    ///     primaryProvider: adaptyProvider,
//    ///     fallbackUI: MyPaywallViewController.self,   // ← твій клас
//    ///     validator: subscriptionService
//    /// )
//    /// ```
//    @MainActor
//    static func configure(
//        configuration: PaywallKitConfiguration,
//        primaryProvider: PaywallProvider,
//        fallbackUI: (any PaywallKitUI.Type)?,
//        validator: SubscriptionValidator,
//        eventHandler: PurchaseEventHandler? = nil
//    ) {
//        let fallbackProvider: StoreKitProvider? = fallbackUI.map { uiType in
//            StoreKitProvider(
//                productIds: configuration.productIds,
//                validator: validator,
//                paywallFactory: ProtocolBasedPaywallFactory(uiType: uiType)
//            )
//        }
//
//        PaywallKit.configure(
//            configuration: configuration,
//            primaryProvider: primaryProvider,
//            fallbackProvider: fallbackProvider,
//            validator: validator,
//            eventHandler: eventHandler
//        )
//    }
//}

// MARK: - ProtocolBasedPaywallFactory (internal)

/// Фабрика що створює PaywallKitUI-контролер і пробрасує context.
final class ProtocolBasedPaywallFactory: StoreKitPaywallFactory {

    private let uiType: any PaywallKitUI.Type

    init(uiType: any PaywallKitUI.Type) {
        self.uiType = uiType
    }

    @MainActor
    func makeController(products: [Product], placementId: String, delegate: StoreKitPaywallDelegate, accentColor: UIColor) -> UIViewController {
        // Конвертуємо StoreKit Product → PaywallProduct
        var paywallProducts = products.map { PaywallProduct(from: $0) }
        
        // Позначаємо найпопулярніший продукт
        if paywallProducts.count > 1,
           let maxIdx = paywallProducts.indices.max(by: { paywallProducts[$0].displayPrice < paywallProducts[$1].displayPrice }) {
            paywallProducts[maxIdx].isPopular = true
        }

        // Weak ref на controller для delegate callbacks (безпечніше ніж UIApplication.shared.topViewController)
        weak var controllerRef: UIViewController?

        // Створюємо context з callbacks → delegate
        let context = PaywallUIContext(
            products: paywallProducts,
            placementId: placementId,
            accentColor: accentColor,
            purchase: { [weak delegate] product in
                // Конвертуємо назад у StoreKit Product
                guard let original = products.first(where: { $0.id == product.id }),
                      let vc = controllerRef else { return }
                delegate?.paywallDidRequestPurchase(original, from: vc)
            },
            restore: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidRequestRestore(from: vc)
            },
            close: { [weak delegate] in
                guard let vc = controllerRef else { return }
                delegate?.paywallDidClose(vc)
            }
        )

        let controller = uiType.make(context: context)
        controllerRef = controller
        return controller
    }
}

// MARK: - PaywallProduct(from:) StoreKit initializer

extension PaywallProduct {
    init(from product: Product) {
        self.id = product.id
        self.displayName = product.displayName
        self.description = product.description
        self.displayPrice = product.displayPrice
        self.pricePerMonth = nil // Можна розрахувати з subscription info
        self.introductoryOffer = product.subscription?.introductoryOffer?.period.debugDescription
        self.subscriptionPeriod = SubscriptionPeriod(from: product.subscription?.subscriptionPeriod)
    }
}

extension SubscriptionPeriod {
    init(from period: Product.SubscriptionPeriod?) {
        guard let period else { self = .unknown; return }
        switch period.unit {
        case .week:  self = .weekly
        case .month: self = period.value >= 3 ? .quarterly : .monthly
        case .year:  self = .yearly
        case .day:   self = .unknown
        @unknown default: self = .unknown
        }
    }
}

// MARK: - UIApplication helper (internal)

private extension UIApplication {
    var topViewController: UIViewController? {
        guard let windowScene = connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController
        else { return nil }
        return root.topPresentedViewController
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        presentedViewController?.topPresentedViewController ?? self
    }
}
