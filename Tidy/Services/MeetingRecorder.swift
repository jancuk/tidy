import AppKit
import AVFoundation
import ScreenCaptureKit

struct MeetingCaptureApp: Identifiable, Equatable {
    var id: Int32
    var name: String
    var bundleID: String? = nil

    static var running: [Self] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { Self(id: $0.processIdentifier, name: $0.localizedName ?? "Application", bundleID: $0.bundleIdentifier) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

final class MeetingAudioSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct Track {
        var file: AVAudioFile
        var chunk: MeetingAudioChunk
        var frames: Int64 = 0
        var peak: Float = 0
    }

    private let lock = NSLock()
    private let directory: URL
    private let epoch: TimeInterval
    private let chunkDuration: TimeInterval
    private var tracks: [String: Track] = [:]
    private var chunks: [MeetingAudioChunk] = []
    private var closed = false
    private var peaks: [String: Float] = [:]
    var onError: ((String) -> Void)?

    init(directory: URL, epoch: TimeInterval, chunkDuration: TimeInterval = 60) {
        self.directory = directory
        self.epoch = epoch
        self.chunkDuration = min(60, max(5, chunkDuration))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        report("Call audio capture stopped: \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio || outputType == .microphone,
              sampleBuffer.isValid, let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = sampleBuffer.numSamples
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        guard status == noErr else { report("Could not read captured audio (\(status))."); return }
        append(buffer, source: outputType == .audio ? "Call" : "Microphone", time: sampleBuffer.presentationTimeStamp.seconds)
    }

    func append(_ buffer: AVAudioPCMBuffer, source: String, time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, buffer.frameLength > 0, buffer.format.sampleRate > 0, time.isFinite else { return }
        let start = max(0, time - epoch)
        guard start < MeetingLimits.maximumRecordingDuration else { return }
        let originalLength = buffer.frameLength
        let remainingFrames = floor((MeetingLimits.maximumRecordingDuration - start) * buffer.format.sampleRate)
        buffer.frameLength = AVAudioFrameCount(min(Double(originalLength), remainingFrames))
        defer { buffer.frameLength = originalLength }
        guard buffer.frameLength > 0 else { return }
        do {
            if let track = tracks[source] {
                let expected = track.chunk.start + Double(track.frames) / track.file.processingFormat.sampleRate
                if track.chunk.duration >= chunkDuration || track.frames * Int64(buffer.format.channelCount) * 2 >= 10_000_000
                    || track.file.processingFormat != buffer.format || abs(start - expected) > 0.5 {
                    try finishTrack(source)
                }
            }
            if tracks[source] == nil {
                let chunk = MeetingAudioChunk(fileName: UUID().uuidString + ".wav", source: source, start: start,
                                              duration: 0, hasSpeechLevelAudio: true)
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: buffer.format.sampleRate, AVNumberOfChannelsKey: buffer.format.channelCount,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
                let url = directory.appendingPathComponent(chunk.fileName)
                let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: buffer.format.commonFormat,
                                           interleaved: buffer.format.isInterleaved)
                SecureLocalStorage.protectFile(at: url)
                try writeMetadata(chunk)
                tracks[source] = Track(file: file, chunk: chunk)
            }
            guard var track = tracks[source] else { return }
            let trackFramesRemaining = floor((MeetingLimits.maximumRecordingDuration - track.chunk.start) * buffer.format.sampleRate) - Double(track.frames)
            guard trackFramesRemaining > 0 else { return }
            buffer.frameLength = AVAudioFrameCount(min(Double(buffer.frameLength), trackFramesRemaining))
            guard buffer.frameLength > 0 else { return }
            try track.file.write(from: buffer)
            track.frames += Int64(buffer.frameLength)
            track.chunk.duration = Double(track.frames) / buffer.format.sampleRate
            var peak: Float = 0
            if let channels = buffer.floatChannelData {
                let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
                for channel in 0..<Int(buffer.format.channelCount) {
                    let samples = channels[buffer.format.isInterleaved ? 0 : channel]
                    let offset = buffer.format.isInterleaved ? channel : 0
                    for index in Swift.stride(from: 0, to: Int(buffer.frameLength), by: 8) {
                        peak = max(peak, abs(samples[index * stride + offset]))
                    }
                }
            } else { peak = 1 }
            track.peak = max(track.peak, peak)
            peaks[source] = max(peaks[source] ?? 0, peak)
            tracks[source] = track
        } catch { report("Could not save meeting audio: \(error.localizedDescription)") }
    }

    func levels() -> [String: Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = peaks
        peaks = [:]
        return result
    }

    func finish() throws -> [MeetingAudioChunk] {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        for source in Array(tracks.keys) { try finishTrack(source) }
        return chunks.sorted { $0.start < $1.start }
    }

    func completedChunks() -> [MeetingAudioChunk] {
        lock.lock()
        defer { lock.unlock() }
        return chunks.sorted { $0.start < $1.start }
    }

    private func finishTrack(_ source: String) throws {
        guard let track = tracks.removeValue(forKey: source) else { return }
        var chunk = track.chunk
        chunk.hasSpeechLevelAudio = track.peak > 0.002
        try writeMetadata(chunk)
        chunks.append(chunk)
    }

    private func writeMetadata(_ chunk: MeetingAudioChunk) throws {
        let url = directory.appendingPathComponent(chunk.fileName + ".json")
        try JSONEncoder().encode(chunk).write(to: url, options: .atomic)
        SecureLocalStorage.protectFile(at: url)
    }

    private func report(_ error: String) {
        // Capture callbacks must never synchronously call back into the sink.
        onError?(error)
    }
}

@MainActor
protocol MeetingRecording: AnyObject {
    var onError: ((String) -> Void)? { get set }
    var elapsed: TimeInterval { get }
    func start(mode: MeetingMode, appID: Int32?, callAudioSource: MeetingCallAudioSource, directory: URL, chunkDuration: TimeInterval) async throws
    func levels() -> [String: Float]
    func completedChunks() -> [MeetingAudioChunk]
    func stop() async throws -> [MeetingAudioChunk]
}

@MainActor
final class MeetingRecorder: MeetingRecording {
    private var engine: AVAudioEngine?
    private var stream: SCStream?
    private var sink: MeetingAudioSink?
    private var epoch: TimeInterval?
    var elapsed: TimeInterval {
        guard let epoch else { return 0 }
        return max(0, CMClockGetTime(CMClockGetHostTimeClock()).seconds - epoch)
    }
    var onError: ((String) -> Void)?

    func start(mode: MeetingMode, appID: Int32?, callAudioSource: MeetingCallAudioSource, directory: URL, chunkDuration: TimeInterval) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw MeetingError.message("Allow Tidy to use the microphone in System Settings → Privacy & Security → Microphone.")
        }
        var callFilter: SCContentFilter?
        if mode == .call {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            } catch {
                throw MeetingError.message("Could not access call audio. Allow Tidy in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Tidy and retry. \(error.localizedDescription)")
            }
            guard let display = content.displays.first else {
                throw MeetingError.message("No display is available for system audio capture. Connect a display and try again.")
            }
            switch callAudioSource {
            case .system:
                // Browser audio can originate in helper processes outside the selected app filter.
                callFilter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            case .application:
                guard let app = content.applications.first(where: { $0.processID == appID }) else {
                    throw MeetingError.message("The selected call app is no longer available. Refresh the app list and select it again, or choose System audio for Google Meet.")
                }
                callFilter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            }
        }
        let epoch = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        self.epoch = epoch
        let sink = MeetingAudioSink(directory: directory, epoch: epoch, chunkDuration: chunkDuration)
        sink.onError = { [weak self] message in Task { @MainActor in self?.onError?(message) } }
        self.sink = sink
        do {
            if mode == .inPerson {
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    throw MeetingError.message("No microphone is available. Connect an input device and try again.")
                }
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                    sink.append(buffer, source: "Room", time: AVAudioTime.seconds(forHostTime: time.hostTime))
                }
                self.engine = engine
                try engine.start()
            } else {
                guard let filter = callFilter else { throw MeetingError.message("Select a call app.") }
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.captureMicrophone = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 24000
                configuration.channelCount = 1
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
                let queue = DispatchQueue(label: "Tidy.MeetingCapture", qos: .userInitiated)
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: queue)
                try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: queue)
                self.stream = stream
                try await stream.startCapture()
            }
        } catch {
            _ = try? await stop()
            throw error
        }
    }

    func levels() -> [String: Float] { sink?.levels() ?? [:] }
    func completedChunks() -> [MeetingAudioChunk] { sink?.completedChunks() ?? [] }

    func stop() async throws -> [MeetingAudioChunk] {
        defer { epoch = nil }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        let stream = self.stream
        self.stream = nil
        var stopError: Error?
        if let stream { do { try await stream.stopCapture() } catch { stopError = error } }
        let sink = self.sink
        self.sink = nil
        let chunks = try sink?.finish() ?? []
        if let stopError { throw stopError }
        return chunks
    }
}
