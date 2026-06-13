import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?

    func toggleRecording() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        do {
            if #available(iOS 17.0, *) {
                let granted = await AVAudioApplication.requestRecordPermission()
                guard granted else {
                    errorMessage = "Microphone permission was denied."
                    return
                }
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("smart-shadow-\(Int(Date().timeIntervalSince1970)).m4a")
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

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
