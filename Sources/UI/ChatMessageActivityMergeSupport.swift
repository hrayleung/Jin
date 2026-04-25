import Collections
import Foundation

enum ChatMessageActivityMergeSupport {
    static func mergedSearchActivities(
        existingData: Data?,
        newActivities: [SearchActivity],
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) -> Data? {
        let existingActivities = decoded([SearchActivity].self, from: existingData, using: decoder) ?? []
        let mergedActivities = mergeOrderedByID(existingActivities, with: newActivities) { existing, incoming in
            existing.merged(with: incoming)
        }
        return mergedActivities.isEmpty ? nil : try? encoder.encode(mergedActivities)
    }

    static func mergedAgentToolActivities(
        existingData: Data?,
        newActivities: [CodexToolActivity],
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) -> Data? {
        let existingActivities = decoded([CodexToolActivity].self, from: existingData, using: decoder) ?? []
        let mergedActivities = mergeOrderedByID(existingActivities, with: newActivities) { existing, incoming in
            existing.merged(with: incoming)
        }
        return mergedActivities.isEmpty ? nil : try? encoder.encode(mergedActivities)
    }

    private static func decoded<T: Decodable>(_ type: T.Type, from data: Data?, using decoder: JSONDecoder) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func mergeOrderedByID<Activity>(
        _ existingActivities: [Activity],
        with newActivities: [Activity],
        merge: (Activity, Activity) -> Activity
    ) -> [Activity] where Activity: Identifiable, Activity.ID == String {
        var byID: OrderedDictionary<String, Activity> = [:]

        for activity in existingActivities {
            byID[activity.id] = activity
        }

        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = merge(existing, activity)
            } else {
                byID[activity.id] = activity
            }
        }

        return Array(byID.values)
    }
}
