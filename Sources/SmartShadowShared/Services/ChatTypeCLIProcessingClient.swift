import Foundation

#if os(macOS)
public enum ChatTypeCLIProcessingError: LocalizedError, Equatable {
    case commandFailed(Int32, String)
    case invalidResponse
    case missingPolishedText

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(status, output):
            "ChatType CLI failed with status \(status): \(output)"
        case .invalidResponse:
            "ChatType CLI returned an invalid response."
        case .missingPolishedText:
            "ChatType CLI response did not contain polished text."
        }
    }
}

public final class ChatTypeCLIProcessingClient: LocalVoiceProcessingClient {
    private let executableURL: URL
    private let environment: [String: String]
    private var cachedAudioURL: URL?
    private var cachedResult: LocalVoiceProcessedTask?

    public init(executableURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executableURL = executableURL
        self.environment = environment
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let result = try await run(audioURL: audioURL)
        cachedAudioURL = audioURL
        cachedResult = result
        return result.transcript
    }

    public func polish(transcript: String) async throws -> String {
        guard let cachedResult else {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let polished = cachedResult.polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !polished.isEmpty else { throw ChatTypeCLIProcessingError.missingPolishedText }
        return polished
    }

    private func run(audioURL: URL) async throws -> LocalVoiceProcessedTask {
        if let cachedResult, cachedAudioURL == audioURL {
            return cachedResult
        }
        let result = try await Self.runProcess(executableURL: executableURL, audioURL: audioURL, environment: environment)
        return result
    }

    private static func runProcess(
        executableURL: URL,
        audioURL: URL,
        environment: [String: String]
    ) async throws -> LocalVoiceProcessedTask {
        try await Task.detached {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["process", "--audio", audioURL.path, "--format", "json"]
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let combinedOutput = [
                String(data: output, encoding: .utf8),
                String(data: errorOutput, encoding: .utf8)
            ]
                .compactMap { $0 }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard process.terminationStatus == 0 else {
                throw ChatTypeCLIProcessingError.commandFailed(process.terminationStatus, combinedOutput)
            }
            guard
                let json = try JSONSerialization.jsonObject(with: output) as? [String: Any],
                let transcript = json["transcript"] as? String
            else {
                throw ChatTypeCLIProcessingError.invalidResponse
            }
            let polished = (json["polished_text"] as? String) ?? (json["polishedText"] as? String) ?? transcript
            return LocalVoiceProcessedTask(
                transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                polishedText: polished.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.value
    }
}
#endif
