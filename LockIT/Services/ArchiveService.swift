import Foundation
import ZIPFoundation

enum ArchiveServiceError: Error {
    case zipFailed
    case unzipFailed
}

final class ArchiveService {
    static let shared = ArchiveService()
    private init() {}

    func zipFolder(at folderURL: URL, to destinationZip: URL) throws {
        print("📦 Zipping folder: \(folderURL.path)")
        let fm = FileManager()
        if fm.fileExists(atPath: destinationZip.path) {
            try fm.removeItem(at: destinationZip)
        }
        
        let archive: Archive
        do {
            archive = try Archive(url: destinationZip, accessMode: .create)
        } catch {
            throw ArchiveServiceError.zipFailed
        }
        
        let folderName = folderURL.lastPathComponent
        let parentURL = folderURL.deletingLastPathComponent()
        
        // For empty folders, we'll create a placeholder file to ensure folder structure is preserved
        let hasContents = fm.enumerator(at: folderURL, includingPropertiesForKeys: nil)?.nextObject() != nil
        if !hasContents {
            print("📁 Empty folder detected, adding placeholder file")
            let placeholderPath = folderName + "/.lockit_placeholder"
            let placeholderData = "This file ensures empty folder structure is preserved".data(using: .utf8) ?? Data()
            try archive.addEntry(with: placeholderPath, type: .file, uncompressedSize: Int64(placeholderData.count), compressionMethod: .deflate, provider: { _, _ in
                return placeholderData
            })
        }
        
        // Add the folder contents, preserving the folder structure
        if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                let relativePath = fileURL.path.replacingOccurrences(of: parentURL.path + "/", with: "")
                print("📁 Adding to zip: \(relativePath)")
                
                var isDirectory: ObjCBool = false
                fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
                
                if !isDirectory.boolValue {
                    // Only add files, not directories (ZIPFoundation handles directories automatically)
                    try archive.addEntry(with: relativePath, relativeTo: parentURL)
                }
            }
        }
    }

    func unzipArchive(at archiveURL: URL, to destinationDirectory: URL) throws {
        print("📦 Unzipping archive: \(archiveURL.path)")
        print("📁 Extracting to directory: \(destinationDirectory.path)")
        
        do {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            let fm = FileManager.default
            
            for entry in archive {
                print("📄 Extracting: \(entry.path) (type: \(entry.type))")
                
                if entry.type == .directory {
                    // Create directory
                    let dirURL = destinationDirectory.appendingPathComponent(entry.path)
                    print("📁 Creating directory: \(dirURL.path)")
                    try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                } else {
                    // Extract file
                    let destinationURL = destinationDirectory.appendingPathComponent(entry.path)
                    print("📄 Extracting file to: \(destinationURL.path)")
                    
                    // Skip placeholder files
                    if entry.path.hasSuffix("/.lockit_placeholder") {
                        print("🗑️ Skipping placeholder file: \(entry.path)")
                        continue
                    }
                    
                    // Create parent directories if needed
                    let parentDir = destinationURL.deletingLastPathComponent()
                    if !fm.fileExists(atPath: parentDir.path) {
                        print("📁 Creating parent directory: \(parentDir.path)")
                        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }
                    
                    // Extract the file data and write it manually
                    var fileData = Data()
                    _ = try archive.extract(entry, bufferSize: 32*1024, skipCRC32: true) { data in
                        fileData.append(data)
                    }
                    
                    try fileData.write(to: destinationURL)
                    print("✅ File extracted successfully: \(destinationURL.path)")
                }
            }
            
            print("✅ Unzip completed")
        } catch {
            print("❌ Unzip failed: \(error)")
            throw ArchiveServiceError.unzipFailed
        }
    }
}

