import AVFoundation
import Foundation

@MainActor
public final class VoiceRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public private(set) var isRecording = false
    @Published public private(set) var recordingURL: URL?
    @Published public var errorMessage: String?

    private var recorder: AVAudioRecorder?

    public override init() {
        super.init()
    }

    public func startRecording(to url: URL) async {
        do {
            guard await requestMicrophonePermission() else {
                errorMessage = "Microphone permission was denied."
                return
            }

            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()
            self.recorder = recorder
            recordingURL = url
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }

    public func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    private func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
        #endif
    }
}
