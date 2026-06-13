import Foundation

public protocol LocalVoiceProcessingClient {
    func transcribe(audioURL: URL) async throws -> String
    func polish(transcript: String) async throws -> String
}

public struct LocalVoiceProcessedTask: Equatable, Sendable {
    public var transcript: String
    public var polishedText: String

    public init(transcript: String, polishedText: String) {
        self.transcript = transcript
        self.polishedText = polishedText
    }
}

public struct LocalVoiceProcessingPipeline {
    private let client: any LocalVoiceProcessingClient

    public init(client: any LocalVoiceProcessingClient) {
        self.client = client
    }

    public func process(audioURL: URL) async throws -> LocalVoiceProcessedTask {
        let transcript = try await client.transcribe(audioURL: audioURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = try await client.polish(transcript: transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalVoiceProcessedTask(transcript: transcript, polishedText: polished)
    }
}
