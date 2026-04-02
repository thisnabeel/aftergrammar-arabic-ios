import AVFoundation
import Combine
import Foundation
import SwiftUI

struct LocalRecording: Identifiable, Codable, Hashable {
    let id: UUID
    /// Chapter this recording belongs to. Optional for backward-compatible decoding.
    let chapterId: Int?
    let fileName: String
    let createdAt: Date
    let durationSeconds: Double?
    let waveform: [Float]?

    var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}

@MainActor
final class LocalRecordingsStore: ObservableObject {
    @Published private(set) var recordings: [LocalRecording] = []

    private let defaultsKey = "local_recordings_v1"
    private let chapterId: Int
    private var all: [LocalRecording] = []

    init(chapterId: Int) {
        self.chapterId = chapterId
        load()
    }

    func add(_ recording: LocalRecording, chapterId: Int) {
        let scoped = LocalRecording(
            id: recording.id,
            chapterId: chapterId,
            fileName: recording.fileName,
            createdAt: recording.createdAt,
            durationSeconds: recording.durationSeconds,
            waveform: recording.waveform
        )
        all.insert(scoped, at: 0)
        recordings = all.filter { $0.chapterId == self.chapterId }
        save()
    }

    func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { recordings[$0] }
        let ids = Set(toDelete.map(\.id))
        recordings.remove(atOffsets: offsets)
        all.removeAll { ids.contains($0.id) }
        save()

        for r in toDelete {
            try? FileManager.default.removeItem(at: r.url)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LocalRecording].self, from: data) else {
            all = []
            recordings = []
            return
        }
        all = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        recordings = all.filter { $0.chapterId == chapterId }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

@MainActor
final class AudioRecorderController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case recording
        case saving
        case failed(String)
        case permissionDenied
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentFileName: String?
    @Published private(set) var liveWaveform: [Float] = []

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    func toggleRecording(onSaved: @escaping (LocalRecording) -> Void) {
        switch state {
        case .recording:
            stop(onSaved: onSaved)
        case .idle, .failed, .permissionDenied:
            Task { @MainActor in
                await start()
            }
        case .saving:
            break
        }
    }

    func start() async {
        let allowed = await requestPermissionIfNeeded()
        guard allowed else {
            state = .permissionDenied
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)

            let fileName = "recording-\(ISO8601DateFormatter().string(from: Date())).m4a"
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.isMeteringEnabled = true
            r.prepareToRecord()
            r.record()

            recorder = r
            currentFileName = fileName
            liveWaveform = []
            state = .recording

            startMetering()
        } catch {
            state = .failed(error.localizedDescription)
            recorder = nil
            currentFileName = nil
        }
    }

    func stop(onSaved: @escaping (LocalRecording) -> Void) {
        guard let recorder, let fileName = currentFileName else {
            state = .idle
            return
        }

        state = .saving
        stopMetering()
        recorder.stop()
        self.recorder = nil

        let duration = recorder.currentTime
        let recording = LocalRecording(
            id: UUID(),
            chapterId: nil,
            fileName: fileName,
            createdAt: Date(),
            durationSeconds: duration > 0 ? duration : nil,
            waveform: liveWaveform.isEmpty ? nil : downsample(liveWaveform, targetCount: 180)
        )
        currentFileName = nil
        liveWaveform = []
        state = .idle
        onSaved(recording)
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 22.0, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            let power = r.averagePower(forChannel: 0) // typically [-160, 0]
            let normalized = Self.normalizePower(power)
            self.liveWaveform.append(normalized)
            // Keep memory bounded for long recordings (cap ~3 minutes at 22 Hz).
            if self.liveWaveform.count > 22 * 180 {
                self.liveWaveform.removeFirst(self.liveWaveform.count - (22 * 180))
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private static func normalizePower(_ power: Float) -> Float {
        // Map [-60, 0] dB roughly into [0, 1] with a soft curve.
        let clamped = max(-60, min(0, power))
        let linear = powf(10, clamped / 20) // [0.001, 1]
        let boosted = sqrtf(linear)         // emphasize quiet parts
        return max(0, min(1, boosted))
    }

    private func downsample(_ input: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0, !input.isEmpty else { return [] }
        if input.count <= targetCount { return input }
        let stride = Double(input.count) / Double(targetCount)
        return (0 ..< targetCount).map { i in
            let start = Int(Double(i) * stride)
            let end = min(input.count, Int(Double(i + 1) * stride))
            if start >= end { return input[min(start, input.count - 1)] }
            let slice = input[start..<end]
            // Peak per bucket looks better than avg for waveform.
            return slice.max() ?? 0
        }
    }

    private func requestPermissionIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { cont in
                    AVAudioApplication.requestRecordPermission { ok in
                        cont.resume(returning: ok)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { cont in
                    AVAudioSession.sharedInstance().requestRecordPermission { ok in
                        cont.resume(returning: ok)
                    }
                }
            @unknown default:
                return false
            }
        }
    }
}

@MainActor
final class AudioPlayerController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentID: UUID?
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func togglePlay(_ recording: LocalRecording) {
        if currentID == recording.id, isPlaying {
            stop()
            return
        }
        play(recording)
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentID = nil
        duration = 0
        currentTime = 0
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        currentTime = player.currentTime
        if !player.isPlaying, isPlaying {
            player.play()
        }
    }

    private func play(_ recording: LocalRecording) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: recording.url)
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
            currentID = recording.id
            duration = p.duration
            currentTime = p.currentTime

            progressTimer?.invalidate()
            progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.stop()
                }
            }
        } catch {
            stop()
        }
    }
}

