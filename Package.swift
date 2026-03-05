// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSceneKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "OnboardingKit", targets: ["OnboardingKit"]),
        .library(name: "PaywallKit",    targets: ["PaywallKit"]),
        .library(name: "RatingKit",     targets: ["RatingKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "OnboardingKit",
            path: "Sources/OnboardingKit"
        ),
        .target(
            name: "PaywallKit",
            dependencies: [
                .product(name: "Adapty",   package: "AdaptySDK-iOS"),
                .product(name: "AdaptyUI", package: "AdaptySDK-iOS")
            ],
            path: "Sources/PaywallKit"
        ),
        .target(
            name: "RatingKit",
            dependencies: [
                "PaywallKit"
            ],
            path: "Sources/Ratingkit"
        ),
    ]
)
