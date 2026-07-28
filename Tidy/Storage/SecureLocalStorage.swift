import Foundation

enum SecureLocalStorage {
    static let ownerDirectoryPermissions: Int16 = 0o700
    static let ownerFilePermissions: Int16 = 0o600

    static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Tidy", isDirectory: true)
        ensureOwnerOnlyDirectory(at: directory, fileManager: fileManager)
        return directory
    }

    static func ensureOwnerOnlyDirectory(
        at directory: URL,
        fileManager: FileManager = .default
    ) {
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: ownerDirectoryPermissions)]
        )
        chmod(directory.path, mode_t(ownerDirectoryPermissions))
    }

    static func protectFile(at url: URL) {
        chmod(url.path, mode_t(ownerFilePermissions))
    }
}
