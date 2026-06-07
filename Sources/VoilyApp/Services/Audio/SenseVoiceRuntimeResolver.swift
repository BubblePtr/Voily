import Foundation

struct SenseVoiceRuntimeResolver {
    private let bundleURL: URL
    private let environment: [String: String]

    init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.bundleURL = bundle.bundleURL
        self.environment = environment
    }

    var isRuntimeAvailable: Bool {
        resolvePythonURL() != nil
    }

    func resolvePythonURL() -> URL? {
        let candidates = [
            bundledRuntimeRootURL()?
                .appending(path: "python")
                .appending(path: "bin")
                .appending(path: "python3"),
            environmentPythonURL(),
        ]

        return candidates.compactMap { $0 }.first { pythonURL in
            FileManager.default.isExecutableFile(atPath: pythonURL.path)
        }
    }

    func resolvePythonPath() throws -> String {
        guard let pythonURL = resolvePythonURL() else {
            throw SenseVoiceResidentServiceError.pythonNotFound
        }
        return pythonURL.path
    }

    func bundledServerScriptURL() -> URL? {
        guard let runtimeRoot = bundledRuntimeRootURL() else {
            return nil
        }
        let scriptURL = runtimeRoot
            .appending(path: "server")
            .appending(path: "sensevoice_resident_server.py")
        return FileManager.default.fileExists(atPath: scriptURL.path) ? scriptURL : nil
    }

    func environmentOverrides(for pythonURL: URL) -> [String: String] {
        guard let runtimeRoot = bundledRuntimeRootURL(),
              pythonURL.standardizedFileURL.path.hasPrefix(runtimeRoot.standardizedFileURL.path + "/") else {
            return [:]
        }

        let pythonHome = runtimeRoot.appending(path: "python")
        let pythonLib = pythonHome.appending(path: "lib")
        var overrides = [
            "PYTHONHOME": pythonHome.path,
            "PYTHONNOUSERSITE": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
        ]

        if let existingLibraryPath = environment["DYLD_LIBRARY_PATH"], !existingLibraryPath.isEmpty {
            overrides["DYLD_LIBRARY_PATH"] = "\(pythonLib.path):\(existingLibraryPath)"
        } else {
            overrides["DYLD_LIBRARY_PATH"] = pythonLib.path
        }

        return overrides
    }

    private func environmentPythonURL() -> URL? {
        guard let rawValue = environment["VOILY_SENSEVOICE_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rawValue)
    }

    func bundledRuntimeRootURL() -> URL? {
        bundleURL
            .appending(path: "Contents")
            .appending(path: "Library")
            .appending(path: "SenseVoiceRuntime")
    }
}
