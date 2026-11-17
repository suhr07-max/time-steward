// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TimeSteward", platforms: [.macOS(.v13)], products: [.executable(name: "TimeSteward", targets: ["TimeSteward"]), .executable(name: "CoreChecks", targets: ["CoreChecks"])], targets: [.target(name: "StewardCore"), .executableTarget(name: "TimeSteward", dependencies: ["StewardCore"]), .executableTarget(name: "CoreChecks", dependencies: ["StewardCore"], path: "Tests/StewardCoreTests")])
