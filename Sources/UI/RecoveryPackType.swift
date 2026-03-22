import UniformTypeIdentifiers

enum RecoveryPackType {
    static let type = UTType(filenameExtension: "jinbackup") ?? .data
}
