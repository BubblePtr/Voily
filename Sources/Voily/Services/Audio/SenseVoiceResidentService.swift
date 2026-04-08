import Foundation

enum SenseVoiceResidentServiceError: LocalizedError {
    case pythonNotFound
    case startupFailed(String)
    case serverUnavailable
    case invalidResponse
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "未找到可用的 SenseVoice MLX 运行时。"
        case let .startupFailed(message):
            return "SenseVoice 常驻服务启动失败：\(message)"
        case .serverUnavailable:
            return "SenseVoice 常驻服务未就绪。"
        case .invalidResponse:
            return "SenseVoice 常驻服务返回了无效响应。"
        case .emptyTranscript:
            return "SenseVoice 常驻服务未返回可用文本。"
        }
    }
}

struct SenseVoiceResidentSession {
    let id: String
    let language: String
    let sampleRate: Double
}

private struct SenseVoiceStartSessionRequest: Encodable {
    let language: String
    let sampleRate: Double
}

private struct SenseVoiceStartSessionResponse: Decodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

private struct SenseVoiceAppendRequest: Encodable {
    let pcm16Base64: String

    enum CodingKeys: String, CodingKey {
        case pcm16Base64 = "pcm16_base64"
    }
}

private struct SenseVoicePartialResponse: Decodable {
    let text: String
    let changed: Bool
}

private struct SenseVoiceFinalizeResponse: Decodable {
    let text: String
}

actor SenseVoiceResidentService {
    private let port = 50231
    private let partialMinimumDurationMs = 1500
    private var process: Process?

    func startSession(sampleRate: Double, languageCode: String) async throws -> SenseVoiceResidentSession {
        try await ensureServerStarted()
        let body = SenseVoiceStartSessionRequest(
            language: normalizedLanguageCode(languageCode),
            sampleRate: sampleRate
        )
        let response: SenseVoiceStartSessionResponse = try await sendJSONRequest(
            path: "/sessions/start",
            body: body,
            timeout: 5
        )
        return SenseVoiceResidentSession(
            id: response.sessionID,
            language: body.language,
            sampleRate: sampleRate
        )
    }

    func appendAudio(sessionID: String, pcm16MonoData: Data) async throws {
        guard !pcm16MonoData.isEmpty else { return }
        let body = SenseVoiceAppendRequest(pcm16Base64: pcm16MonoData.base64EncodedString())
        let _: EmptyResponse = try await sendJSONRequest(
            path: "/sessions/\(sessionID)/append",
            body: body,
            timeout: 10
        )
    }

    func fetchPartial(sessionID: String) async throws -> String? {
        let response: SenseVoicePartialResponse = try await sendJSONRequest(
            path: "/sessions/\(sessionID)/partial",
            body: EmptyRequest(),
            timeout: 30
        )
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, response.changed else {
            return nil
        }
        return text
    }

    func finalizeSession(_ session: SenseVoiceResidentSession) async throws -> LocalASRTranscriptionResult {
        let startedAt = Date()
        let response: SenseVoiceFinalizeResponse = try await sendJSONRequest(
            path: "/sessions/\(session.id)/finalize",
            body: EmptyRequest(),
            timeout: 60
        )
        let duration = Date().timeIntervalSince(startedAt)
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SenseVoiceResidentServiceError.emptyTranscript
        }
        return LocalASRTranscriptionResult(
            text: text,
            duration: duration,
            commandSummary: "sensevoice-resident http://127.0.0.1:\(port)/sessions/\(session.id)/finalize"
        )
    }

    func cancelSession(_ session: SenseVoiceResidentSession) async {
        let request = makeRequest(path: "/sessions/\(session.id)", method: "DELETE", timeout: 5)
        _ = try? await URLSession.shared.data(for: request)
    }

    nonisolated func shouldFetchPartial(elapsedMs: Int) -> Bool {
        elapsedMs >= partialMinimumDurationMs
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func sendJSONRequest<Response: Decodable, RequestBody: Encodable>(
        path: String,
        body: RequestBody,
        timeout: TimeInterval
    ) async throws -> Response {
        try await ensureServerStarted()
        var request = makeRequest(path: path, method: "POST", timeout: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw SenseVoiceResidentServiceError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SenseVoiceResidentServiceError.invalidResponse
        }
    }

    private func makeRequest(path: String, method: String, timeout: TimeInterval) -> URLRequest {
        let requestURL = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = timeout
        return request
    }

    private func ensureServerStarted() async throws {
        if await isHealthy() {
            return
        }

        if let process, process.isRunning {
            throw SenseVoiceResidentServiceError.serverUnavailable
        }

        let pythonPath = try resolvePythonPath()
        let scriptURL = try ensureServerScript()
        let launchResult = try startProcess(pythonPath: pythonPath, scriptURL: scriptURL)
        debugLog("SenseVoice resident launching command=\(launchResult.summary)")

        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(250))
            if await isHealthy() {
                debugLog("SenseVoice resident ready port=\(port)")
                return
            }
            if let process, !process.isRunning {
                let stderr = launchResult.stderrPipe.readSummary()
                self.process = nil
                throw SenseVoiceResidentServiceError.startupFailed(stderr.isEmpty ? "进程提前退出" : stderr)
            }
        }

        throw SenseVoiceResidentServiceError.serverUnavailable
    }

    private func isHealthy() async -> Bool {
        var request = makeRequest(path: "/healthz", method: "GET", timeout: 0.5)
        request.httpBody = nil
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    private func resolvePythonPath() throws -> String {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let appSupportRuntime = applicationSupportRoot()
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent(ASRProvider.senseVoice.rawValue, isDirectory: true)
            .appendingPathComponent("runtime/python/bin/python3", isDirectory: false)
        let candidates: [String?] = [
            environment["VOILY_SENSEVOICE_PYTHON"],
            appSupportRuntime.path,
        ]

        for candidate in candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !candidate.isEmpty {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw SenseVoiceResidentServiceError.pythonNotFound
    }

    private func ensureServerScript() throws -> URL {
        let directory = applicationSupportRoot()
            .appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("sensevoice_resident_server.py")
        try serverScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    private func startProcess(pythonPath: String, scriptURL: URL) throws -> (summary: String, stderrPipe: Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptURL.path, "--port", String(port)]
        process.environment = mergedEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw SenseVoiceResidentServiceError.startupFailed(error.localizedDescription)
        }

        self.process = process
        let summary = ([pythonPath] + (process.arguments ?? [])).joined(separator: " ")
        return (summary, stderrPipe)
    }

    private func mergedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let installedModelDirectory = applicationSupportRoot()
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent(ASRProvider.senseVoice.rawValue, isDirectory: true)
            .appendingPathComponent("model", isDirectory: true)
        environment["SENSEVOICE_MODEL_DIR"] = environment["SENSEVOICE_MODEL_DIR"] ?? installedModelDirectory.path
        return environment
    }

    private func applicationSupportRoot() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL.appendingPathComponent("Voily", isDirectory: true)
    }

    private func normalizedLanguageCode(_ languageCode: String) -> String {
        if languageCode.hasPrefix("zh") {
            return "zh"
        }
        if languageCode.hasPrefix("ja") {
            return "ja"
        }
        if languageCode.hasPrefix("ko") {
            return "ko"
        }
        if languageCode.hasPrefix("yue") {
            return "yue"
        }
        if languageCode.hasPrefix("en") {
            return "en"
        }
        return "auto"
    }

    private var serverScript: String {
        #"""
import argparse
import base64
import os
import tempfile
import threading
import uuid
import wave

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
from mlx_audio.stt import load


class StartRequest(BaseModel):
    language: str = "auto"
    sample_rate: float = 16000


class AppendRequest(BaseModel):
    pcm16_base64: str


class EmptyResponse(BaseModel):
    ok: bool = True


class Session:
    def __init__(self, language: str, sample_rate: float):
        self.language = language or "auto"
        self.sample_rate = int(sample_rate or 16000)
        self.pcm_data = bytearray()
        self.last_partial_text = ""


app = FastAPI()
model_dir = os.getenv("SENSEVOICE_MODEL_DIR")
if not model_dir:
    raise RuntimeError("SENSEVOICE_MODEL_DIR is not set")
model = load(model_dir)
sessions = {}
sessions_lock = threading.Lock()
min_partial_bytes = int(16000 * 2 * 0.6)


def write_wav(path: str, sample_rate: int, pcm_data: bytes):
    with wave.open(path, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm_data)


def transcribe_pcm(session: Session) -> str:
    if not session.pcm_data:
        return ""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wav_file:
        wav_path = wav_file.name
    try:
        write_wav(wav_path, session.sample_rate, session.pcm_data)
        result = model.generate(wav_path, language=session.language, use_itn=True)
        return getattr(result, "text", "").strip()
    finally:
        try:
            os.remove(wav_path)
        except OSError:
            pass


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.post("/sessions/start")
async def start_session(body: StartRequest):
    session_id = str(uuid.uuid4())
    with sessions_lock:
        sessions[session_id] = Session(language=body.language, sample_rate=body.sample_rate)
    return {"session_id": session_id}


@app.post("/sessions/{session_id}/append")
async def append_audio(session_id: str, body: AppendRequest):
    try:
        pcm_chunk = base64.b64decode(body.pcm16_base64)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="invalid pcm16 chunk") from exc
    with sessions_lock:
        session = sessions.get(session_id)
        if session is None:
            raise HTTPException(status_code=404, detail="session not found")
        session.pcm_data.extend(pcm_chunk)
    return {"ok": True}


@app.post("/sessions/{session_id}/partial")
async def fetch_partial(session_id: str):
    with sessions_lock:
        session = sessions.get(session_id)
        if session is None:
            raise HTTPException(status_code=404, detail="session not found")
        pcm_size = len(session.pcm_data)
    if pcm_size < min_partial_bytes:
        return {"text": "", "changed": False}
    text = transcribe_pcm(session)
    changed = False
    with sessions_lock:
        current = sessions.get(session_id)
        if current is None:
            raise HTTPException(status_code=404, detail="session not found")
        if text and text != current.last_partial_text:
            current.last_partial_text = text
            changed = True
    return {"text": text, "changed": changed}


@app.post("/sessions/{session_id}/finalize")
async def finalize_session(session_id: str):
    with sessions_lock:
        session = sessions.pop(session_id, None)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
    text = transcribe_pcm(session)
    return {"text": text}


@app.delete("/sessions/{session_id}")
async def delete_session(session_id: str):
    with sessions_lock:
        sessions.pop(session_id, None)
    return {"ok": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=50231)
    args = parser.parse_args()
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
"""#
    }
}

private struct EmptyRequest: Encodable {}
private struct EmptyResponse: Decodable {}

private extension Pipe {
    func readSummary() -> String {
        let data = fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return ""
        }
        let text = String(decoding: data, as: UTF8.self)
        let compact = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .joined(separator: " | ")
        return compact.count > 400 ? String(compact.prefix(400)) : compact
    }
}
