import Foundation

/// Watches ~/Downloads for new file arrivals and posts a notification
/// so PetBrain can react with curiosity and commentary.
class DownloadsWatcher {
    static let shared = DownloadsWatcher()
    
    /// Posted when a new file lands in ~/Downloads. `object` is the filename (String).
    static let newFileNotification = NSNotification.Name("DownloadsNewFile")
    
    private var source: (any DispatchSourceFileSystemObject)?
    private var fileDescriptor: Int32 = -1
    private var knownFiles: Set<String> = []
    private let queue = DispatchQueue(label: "com.byte.DownloadsWatcher")
    
    private var downloadsURL: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    private init() {}
    
    func startWatching() {
        guard let url = downloadsURL else {
            print("[DownloadsWatcher] Could not locate ~/Downloads")
            return
        }
        
        // Snapshot current contents so we only react to truly new files
        snapshotCurrentFiles()
        
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[DownloadsWatcher] Could not open ~/Downloads for monitoring")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            self?.checkForNewFiles()
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        
        source.resume()
        self.source = source
        print("[DownloadsWatcher] Monitoring ~/Downloads")
    }
    
    func stopWatching() {
        source?.cancel()
        source = nil
    }
    
    private func snapshotCurrentFiles() {
        guard let url = downloadsURL else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            knownFiles = Set(contents.map { $0.lastPathComponent })
        } catch {
            print("[DownloadsWatcher] Failed to snapshot: \(error)")
        }
    }
    
    private func checkForNewFiles() {
        guard let url = downloadsURL else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let currentFiles = Set(contents.map { $0.lastPathComponent })
            let newFiles = currentFiles.subtracting(knownFiles)
            
            for file in newFiles {
                // Skip temporary download fragments
                if file.hasSuffix(".crdownload") || file.hasSuffix(".part") || file.hasSuffix(".download") {
                    continue
                }
                
                print("[DownloadsWatcher] New file: \(file)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: DownloadsWatcher.newFileNotification,
                        object: file
                    )
                }
            }
            
            knownFiles = currentFiles
        } catch {
            print("[DownloadsWatcher] Failed to check: \(error)")
        }
    }
}
