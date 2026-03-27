import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ExportProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.vibeControllerProfile, .json]
    }

    let data: Data

    init(profile: ControllerProfile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.data = try encoder.encode(profile)
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
