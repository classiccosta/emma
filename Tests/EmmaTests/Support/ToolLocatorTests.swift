@testable import Emma
import XCTest

final class ToolLocatorTests: XCTestCase {
    func testFindsToolsInHomeFolders() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = bin.appendingPathComponent("emma-test-tool")
        FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(ToolLocator.find("emma-test-tool", home: home), tool)
    }

    func testRejectsUnsafeNamesAndMissingTools() {
        XCTAssertNil(ToolLocator.find("nope; rm -rf /"))
        XCTAssertNil(ToolLocator.find("definitely-not-installed-tool-xyz"))
    }
}
