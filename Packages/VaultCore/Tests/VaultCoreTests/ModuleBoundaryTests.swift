import Foundation
import Testing

/// VaultCore must stay free of framework imports so its tests run without a
/// simulator and its logic stays portable. This test reads the sources and
/// fails if a forbidden import appears. It is deliberately crude — a grep
/// that runs in CI is worth more than a convention nobody enforces.
@Test("VaultCore imports no UI or persistence frameworks")
func vaultCoreHasNoForbiddenImports() throws {
    let forbidden = ["SwiftUI", "SwiftData", "UIKit", "AppKit", "FoundationModels", "CoreData"]

    let sourcesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // VaultCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // VaultCore
        .appendingPathComponent("Sources/VaultCore")

    let files = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil)!
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }

    #expect(!files.isEmpty, "found no Swift sources to scan at \(sourcesURL.path)")

    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for framework in forbidden {
            #expect(
                !text.contains("import \(framework)"),
                "\(file.lastPathComponent) imports \(framework); VaultCore must stay framework-free"
            )
        }
    }
}
