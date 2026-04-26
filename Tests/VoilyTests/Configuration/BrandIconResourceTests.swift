import XCTest
@testable import Voily

final class BrandIconResourceTests: XCTestCase {
    func testDomesticTextProviderBrandIconsExist() {
        let iconsDirectory = brandIconsDirectoryURL()
        let missingFiles = ["minimax.png", "kimi.png", "zhipu.png"].filter { fileName in
            !FileManager.default.fileExists(atPath: iconsDirectory.appendingPathComponent(fileName).path)
        }

        XCTAssertEqual(missingFiles, [], "Missing brand icons: \(missingFiles.joined(separator: ", "))")
    }

    private func brandIconsDirectoryURL(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Voily/Resources/BrandIcons", isDirectory: true)
    }
}
