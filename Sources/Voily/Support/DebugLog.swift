#if DEBUG
import Foundation

private let debugLogQueue = DispatchQueue(label: "Voily.DebugLogQueue")

func debugLog(_ message: String) {
    debugLogQueue.sync {
        let line = "[Voily] \(message)\n"
        let data = Data(line.utf8)
        let url = URL(fileURLWithPath: "/tmp/voily.log")

        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
#else
@inline(__always)
func debugLog(_ message: String) {
    _ = message
}
#endif
