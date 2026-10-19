// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LightSnap", platforms: [.macOS(.v13)], products: [.executable(name: "LightSnap", targets: ["LightSnap"])], targets: [.executableTarget(name: "LightSnap")])
