import XCTest
@testable import SmartShadowShared

#if os(macOS)
final class ChatTypeCLIProcessingClientTests: XCTestCase {
    func testProcessCommandParsesTranscriptAndPolishedText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-shadow-chattype-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cli = directory.appendingPathComponent("fake-chattype")
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '{"transcript":"%s","polished_text":"%s"}\\n' "原始语音" "最终任务文本"
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let client = ChatTypeCLIProcessingClient(executableURL: cli)
        let transcript = try await client.transcribe(audioURL: URL(fileURLWithPath: "/tmp/input.m4a"))
        let polished = try await client.polish(transcript: transcript)

        XCTAssertEqual(transcript, "原始语音")
        XCTAssertEqual(polished, "最终任务文本")
    }

    func testClientDoesNotReuseCachedResultForDifferentAudioURL() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-shadow-chattype-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cli = directory.appendingPathComponent("fake-chattype")
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail
        audio=""
        while [[ "$#" -gt 0 ]]; do
          case "$1" in
            --audio) audio="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        if [[ "$audio" == *"second"* ]]; then
          printf '{"transcript":"%s","polished_text":"%s"}\\n' "第二条" "第二条最终文本"
        else
          printf '{"transcript":"%s","polished_text":"%s"}\\n' "第一条" "第一条最终文本"
        fi
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let client = ChatTypeCLIProcessingClient(executableURL: cli)
        _ = try await client.transcribe(audioURL: URL(fileURLWithPath: "/tmp/first.m4a"))
        _ = try await client.polish(transcript: "第一条")

        let secondTranscript = try await client.transcribe(audioURL: URL(fileURLWithPath: "/tmp/second.m4a"))
        let secondPolished = try await client.polish(transcript: secondTranscript)

        XCTAssertEqual(secondTranscript, "第二条")
        XCTAssertEqual(secondPolished, "第二条最终文本")
    }
}
#endif
