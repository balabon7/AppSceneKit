// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSceneKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "AppSceneKit", targets: ["AppSceneKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "AppSceneKit",
            dependencies: [
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
                .product(name: "AdaptyUI", package: "AdaptySDK-iOS")
            ],
            path: "Sources"
        ),
    ]
)
