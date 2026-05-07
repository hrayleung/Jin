import Foundation

extension GoogleMapsResultsView {
    func googleMapsEmbedURL(content: MapsContent) -> URL? {
        let locationSuffix: String
        if let bias = locationBias {
            locationSuffix = "/@\(bias.latitude),\(bias.longitude),14z"
        } else {
            locationSuffix = ""
        }

        if let query = content.queries.first {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
            return URL(string: "https://www.google.com/maps/search/\(encoded)\(locationSuffix)")
        }

        if let place = content.places.first {
            let encoded = place.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? place.name
            return URL(string: "https://www.google.com/maps/search/\(encoded)\(locationSuffix)")
        }

        return nil
    }

    func googleMapsOpenURL(content: MapsContent) -> URL? {
        googleMapsEmbedURL(content: content)
    }

    var contextLabel: String? {
        let provider = providerLabel?.trimmedNonEmpty
        let model = modelLabel?.trimmedNonEmpty

        if let provider, let model {
            return "\(provider) / \(model)"
        }
        if let model {
            return model
        }
        return nil
    }
}
