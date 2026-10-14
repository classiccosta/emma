import Foundation

/// Finds command-line tools Emma launches (`uv`, `lms`). Apps started from Finder get a minimal PATH,
/// so the usual install folders are checked first, then the user's login shell is asked.
enum ToolLocator {
    static func find(_ name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let folders = [home.appendingPathComponent(".local/bin"), home.appendingPathComponent(".lmstudio/bin"),
                       home.appendingPathComponent(".cargo/bin"), URL(fileURLWithPath: "/opt/homebrew/bin"),
                       URL(fileURLWithPath: "/usr/local/bin")]
        if let found = folders.map({ $0.appendingPathComponent(name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        return fromLoginShell(name)
    }

    /// `command -v name` in a login shell, which loads the user's PATH from their shell profile.
    private static func fromLoginShell(_ name: String) -> URL? {
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}
