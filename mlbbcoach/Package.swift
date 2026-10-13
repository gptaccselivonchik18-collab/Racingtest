// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CoachCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CoachCore", targets: ["CoachCore"])],
    targets: [
        .target(name: "CoachCore", path: "Core"),
        .target(name: "CoachStorage", path: "App", exclude: ["AdviceJournal.swift", "AppShell.swift", "BrainView.swift", "CoachApp.swift", "DeviceServices.swift", "KnowledgeView.swift", "MatchDetailView.swift", "MemoryView.swift", "ModelManager.swift", "ScreenCaptureService.swift", "StrategyAI.swift", "VideoAnalysisView.swift", "VideoAnalyzer.swift", "VisionEngine.swift", "Info.plist"], sources: ["Storage.swift"]),
        .target(name: "CoachVision", dependencies: ["CoachCore"], path: "App", exclude: ["AdviceJournal.swift", "AppShell.swift", "BrainView.swift", "CoachApp.swift", "DeviceServices.swift", "KnowledgeView.swift", "MatchDetailView.swift", "MemoryView.swift", "ModelManager.swift", "ScreenCaptureService.swift", "Storage.swift", "StrategyAI.swift", "VideoAnalysisView.swift", "VideoAnalyzer.swift", "Info.plist"], sources: ["VisionEngine.swift"]),
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore", "CoachStorage", "CoachVision"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
