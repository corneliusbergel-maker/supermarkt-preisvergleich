// swift-tools-version: 5.9
import PackageDescription

/// Zwei Ebenen, bewusst getrennt:
///
/// - `PriceCore` -- reine Rechen- und Vergleichslogik, ohne Netzwerk.
/// - `PriceData` -- die Anbindung an die offenen Datenquellen.
///
/// Beide ohne Fremdabhaengigkeiten und ohne UIKit/SwiftUI, damit sie auf jedem
/// Mac mit `swift test` geprueft werden koennen -- auch ohne iOS-Simulator.
let package = Package(
    name: "PriceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PriceCore", targets: ["PriceCore"]),
        .library(name: "PriceData", targets: ["PriceData"])
    ],
    targets: [
        .target(name: "PriceCore"),
        .target(name: "PriceData", dependencies: ["PriceCore"]),
        .testTarget(name: "PriceCoreTests", dependencies: ["PriceCore"]),
        .testTarget(name: "PriceDataTests", dependencies: ["PriceData"])
    ]
)
