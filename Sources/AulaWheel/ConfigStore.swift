import AulaWheelCore
import Foundation

/// Loads `config.json` from Application Support and reports when it changes on disk.
final class ConfigStore {
    let directory: URL
    let url: URL
    var onChange: (() -> Void)?

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("AulaWheel", isDirectory: true)
        url = directory.appendingPathComponent("config.json")
    }

    /// Returns the config on disk, writing the defaults first if there is none.
    func load() throws -> AppConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try AppConfig().encoded().write(to: url, options: .atomic)
        }
        return try AppConfig.decode(Data(contentsOf: url))
    }

    /// Watches the directory (editors that save by replacing the file) and the file itself
    /// (editors that write in place).
    func startWatching() {
        if directoryWatcher == nil {
            directoryWatcher = watch(directory.path, events: [.write]) { [weak self] in
                self?.watchFile()
                self?.scheduleReload()
            }
        }
        watchFile()
    }

    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = watch(url.path, events: [.write, .extend, .delete, .rename]) { [weak self] in
            guard let self else { return }
            if let events = self.fileWatcher?.data, !events.isDisjoint(with: [.delete, .rename]) {
                self.watchFile()
            }
            self.scheduleReload()
        }
    }

    private func watch(
        _ path: String, events: DispatchSource.FileSystemEvent, handler: @escaping () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
