import Foundation

final class DirectoryWatcher {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.strictcodeide.watcher", qos: .background)
    
    /// Closure triggered when a change is detected in the directory
    var onDirectoryChanged: (() -> Void)?
    
    deinit {
        stop()
    }
    
    /// Starts watching the specified folder URL
    func start(watching url: URL) {
        stop() // Ensure any existing watcher is cleaned up first
        
        // Open the directory file descriptor (Read-only)
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("DirectoryWatcher Error: Failed to open file descriptor for \(url.path)")
            return
        }
        
        // Monitor for writes (file creation/deletion/renames inside the folder)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )
        
        source?.setEventHandler { [weak self] in
            // Fall back to main thread since this usually triggers UI updates
            DispatchQueue.main.async {
                self?.onDirectoryChanged?()
            }
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        
        source?.resume()
    }
    
    /// Stops watching the directory
    func stop() {
        source?.cancel()
        source = nil
    }
}//
//  DirectoryWatcher.swift
//  StrictCodeIDE
//
//  Created by Shrish Agavane on 10/07/26.
//

