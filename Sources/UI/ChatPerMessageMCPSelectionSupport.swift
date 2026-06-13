import Foundation

enum ChatPerMessageMCPSelectionSupport {
    static func restoredVisibleServerIDs(
        idsData: Data?,
        namesData: Data?,
        decoder: JSONDecoder = JSONDecoder()
    ) -> Set<String> {
        guard let idsData,
              let namesData,
              let ids = try? decoder.decode([String].self, from: idsData),
              let names = try? decoder.decode([String].self, from: namesData),
              !ids.isEmpty,
              !names.isEmpty else {
            return []
        }

        return Set(ids.filter { !$0.isEmpty })
    }
}
