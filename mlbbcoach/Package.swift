// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CoachCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CoachCore", targets: ["CoachCore"])],
    targets: [
        .target(name: "CoachCore", path: "Core"),
        .target(name: "CoachStorage", path: "App", exclude: ["AppShell.swift", "BrainView.swift", "CoachApp.swift", "DeviceServices.swift", "MemoryView.swift", "StrategyAI.swift", "VideoAnalyzer.swift", "VideoAnalysisView.swift", "KnowledgeView.swift"], sources: ["Storage.swift"]),
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore", "CoachStorage"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
