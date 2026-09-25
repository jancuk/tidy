import Foundation

enum MeetingLocalTranscriber {
    static var defaultModelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tidy/Models/ggml-small.bin")
    }

    static func modelURL(defaults: UserDefaults = .standard) -> URL {
        let path = (defaults.string(forKey: AppDefaults.meetingWhisperModelPath) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? defaultModelURL : URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func executableURL(defaults: UserDefaults = .standard) throws -> URL {
        let command = (defaults.string(forKey: AppDefaults.meetingWhisperCLIPath) ?? "whisper-cli")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let executable = try? CodexCLIService.resolvedExecutableURL(for: command.isEmpty ? "whisper-cli" : command) else {
            throw MeetingError.message("Install whisper.cpp and ffmpeg to use local transcription, then choose a Whisper model file in Meetings. Your Codex login handles summaries.")
        }
        return executable
    }

    static func validateSetup() throws {
        _ = try executableURL()
        _ = try converterURL()
        guard FileManager.default.isReadableFile(atPath: modelURL().path) else {
            throw MeetingError.message("Choose a downloaded Whisper GGML model (.bin) in Meetings → Preferences → Local model. Use a multilingual model for Indonesian. No API key is required.")
        }
    }

    private static func converterURL() throws -> URL {
        guard let url = try? CodexCLIService.resolvedExecutableURL(for: "ffmpeg") else {
            throw MeetingError.message("Install ffmpeg to prepare saved audio for local transcription. Your recording is saved.")
        }
        return url
    }

    static func arguments(audio: URL, model: URL, output: URL) -> [String] {
        ["--model", model.path, "--file", audio.path, "--language", "auto",
         "--output-json", "--output-file", output.path, "--no-prints", "--suppress-nst"]
    }

    static func transcribe(_ chunk: MeetingAudioChunk, url: URL) async throws -> [MeetingSegment] {
        try validateSetup()
        let executable = try executableURL()
        let model = modelURL()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidyLocalTranscript-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("audio.wav")
        let output = folder.appendingPathComponent("transcript")
        try await run(executable: converterURL(), arguments: [
            "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe", "-i", url.path,
            "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", audio.path
        ], directory: folder, timeout: 60, name: "Audio conversion")
        SecureLocalStorage.protectFile(at: audio)
        try await run(executable: executable, arguments: arguments(audio: audio, model: model, output: output),
                      directory: folder, timeout: 600, name: "Local Whisper transcription")
        let transcriptURL = output.appendingPathExtension("json")
        SecureLocalStorage.protectFile(at: transcriptURL)
        return try decodeTranscript(Data(contentsOf: transcriptURL), chunk: chunk)
    }

    static func decodeTranscript(_ data: Data, chunk: MeetingAudioChunk) throws -> [MeetingSegment] {
        struct Response: Decodable {
            struct Segment: Decodable {
                struct Offsets: Decodable { var from: Double; var to: Double }
                var offsets: Offsets
                var text: String
            }
            var transcription: [Segment]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard chunk.start.isFinite, chunk.start >= 0, chunk.duration.isFinite, chunk.duration > 0,
              (chunk.start + chunk.duration).isFinite else {
            throw MeetingError.message("The saved audio has invalid timing metadata. Your recording is preserved.")
        }
        return try response.transcription.enumerated().compactMap { index, segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "[BLANK_AUDIO]" else { return nil }
            let start = segment.offsets.from / 1000
            let end = segment.offsets.to / 1000
            // Whisper's final 30-second decoding window can extend past the saved audio.
            guard start.isFinite, end.isFinite, start >= 0, end >= start,
                  end <= chunk.duration + 30 else {
                throw MeetingError.message("Local transcription returned invalid audio timestamps. Your recording is saved; retry transcription.")
            }
            guard start < chunk.duration else { return nil }
            // Whisper supplies timestamps but does not identify speakers in these mono tracks.
            return MeetingSegment(id: "\(chunk.id.uuidString)-\(index)", chunkID: chunk.id,
                                  start: chunk.start + start, end: chunk.start + min(end, chunk.duration),
                                  speaker: chunk.source, text: text)
        }
    }

    static func run(executable: URL, arguments: [String], directory: URL, timeout: TimeInterval, name: String) async throws {
        let log = directory.appendingPathComponent(UUID().uuidString + ".log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin",
                               "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                               "TMPDIR": directory.path, "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try Task.checkCancellation()
        try process.run()
        do {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw MeetingError.message("\(name) timed out. Try a smaller local model; your recording is saved.") }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            if process.isRunning {
                process.terminate()
                await Task.detached {
                    try? await Task.sleep(for: .milliseconds(250))
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit()
                }.value
            }
            throw error
        }
        guard process.terminationStatus == 0 else {
            throw MeetingError.message("\(name) failed (exit \(process.terminationStatus)). Check your Whisper model and local tools. Your recording is saved.")
        }
    }
}
