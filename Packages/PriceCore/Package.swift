// swift-tools-version: 5.9
import PackageDescription

/// PriceCore enthaelt die gesamte Rechen- und Vergleichslogik der App.
///
/// Bewusst OHNE UIKit/SwiftUI und ohne Fremdabhaengigkeiten, damit dieses
/// Paket auf jedem Mac isoliert mit `swift test` geprueft werden kann --
/// auch ohne iOS-Simulator und ohne Xcode-Projekt.
let package = Package(
    name: "PriceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PriceCore", targets: ["PriceCore"])
    ],
    targets: [
        .target(name: "PriceCore"),
        .testTarget(name: "PriceCoreTests", dependencies: ["PriceCore"])
    ]
)
