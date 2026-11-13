// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StockCount",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/getditto/DittoSwiftPackage", exact: "5.2.0"),
    ],
    targets: [
        .target(name: "StockCount", dependencies: [
            .product(name: "DittoSwift", package: "DittoSwiftPackage"),
        ]),
    ]
)
