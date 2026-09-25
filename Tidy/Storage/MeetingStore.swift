import AVFoundation
import Foundation

final class MeetingStore {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = (directory ?? SecureLocalStorage.applicationSupportDirectory()).appendingPathComponent("Meetings", isDirectory: true)
        SecureLocalStorage.ensureOwnerOnlyDirectory(at: self.directory)
    }

    func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }

    func load() -> (records: [MeetingRecord], errors: [String]) {
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var records: [MeetingRecord] = []
            var errors: [String] = []
            for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
                do {
                    var record = try JSONDecoder().decode(MeetingRecord.self, from: Data(contentsOf: folder.appendingPathComponent("meeting.json")))
                    guard record.id.uuidString == folder.lastPathComponent else { throw MeetingError.message("Meeting ID mismatch") }
                    if record.status == .recording || record.status == .processing {
                        record.status = .interrupted
                        record.error = "This meeting was interrupted. Saved audio and completed transcripts are available for retry."
                    }
                    try recoverChunks(in: &record)
                    records.append(record)
                } catch { errors.append("Could not read meeting \(folder.lastPathComponent). Its files have been preserved.") }
            }
            return (records.sorted { $0.createdAt > $1.createdAt }, errors)
        } catch { return ([], ["Could not read meeting history: \(error.localizedDescription)"]) }
    }

    func save(_ record: MeetingRecord) throws {
        let folder = folder(record.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("meeting.json")
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
        SecureLocalStorage.protectFile(at: url)
    }

    func recoverChunks(in record: inout MeetingRecord) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder(record.id), includingPropertiesForKeys: nil)
        var failures = 0
        for file in files where file.lastPathComponent.hasSuffix(".wav.json") {
            do {
                var chunk = try JSONDecoder().decode(MeetingAudioChunk.self, from: Data(contentsOf: file))
                if record.chunks.contains(where: { $0.id == chunk.id }) { continue }
                let audio = try AVAudioFile(forReading: audioURL(chunk, meetingID: record.id))
                chunk.duration = Double(audio.length) / audio.processingFormat.sampleRate
                if chunk.duration > 0 { record.chunks.append(chunk) }
            } catch { failures += 1 }
        }
        if failures > 0 {
            record.status = .interrupted
            record.error = "\(failures) audio part(s) could not be recovered. Other saved audio is available; the original files have been preserved."
        }
        record.chunks.sort { $0.start < $1.start }
        record.duration = max(record.duration, record.chunks.map { $0.start + $0.duration }.max() ?? 0)
    }

    func audioURL(_ chunk: MeetingAudioChunk, meetingID: UUID) throws -> URL {
        guard chunk.fileName == URL(fileURLWithPath: chunk.fileName).lastPathComponent,
              chunk.fileName.hasSuffix(".wav"), !chunk.fileName.contains("..") else {
            throw MeetingError.message("Invalid recording file path.")
        }
        let root = folder(meetingID).resolvingSymlinksInPath()
        let file = root.appendingPathComponent(chunk.fileName).resolvingSymlinksInPath()
        guard file.deletingLastPathComponent() == root else { throw MeetingError.message("Recording points outside its meeting folder.") }
        return file
    }

    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: folder(id)) }
}
