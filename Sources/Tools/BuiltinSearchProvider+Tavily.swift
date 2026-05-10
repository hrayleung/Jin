import Foundation

extension BuiltinSearchToolHub {
    func searchTavily(_ args: ResolvedArguments, route: ToolRoute) async throws -> BuiltinSearchToolOutput {
        var request = URLRequest(url: try validatedURL("https://api.tavily.com/search"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(route.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let body = Self.makeTavilyRequestBody(args: args, settings: route.settings, overrides: route.overrides)
        let clampedMax = args.maxResults.clamped(to: 0...20)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await networkManager.sendRequest(request)
        let json = try parseJSONObject(data)

        let rows = parseArray(json["results"]).prefix(clampedMax).compactMap { item -> SearchCitationRow? in
            guard let url = firstString(in: item, keys: ["url"]) else { return nil }
            let title = firstString(in: item, keys: ["title"]) ?? URL(string: url)?.host ?? url
            let snippet = firstString(
                in: item,
                keys: ["raw_content", "content", "text", "snippet", "summary"]
            )
            return SearchCitationRow(
                title: title,
                url: url,
                snippet: snippet.map { String($0.prefix(500)) },
                publishedAt: firstString(in: item, keys: ["published_date", "publishedDate", "published_at", "published"]),
                source: urlHost(url)
            )
        }

        return BuiltinSearchToolOutput(
            provider: .tavily,
            query: args.query,
            resultCount: rows.count,
            results: rows
        )
    }

    /// Pure builder for the `/search` request body, exposed for tests.
    nonisolated static func makeTavilyRequestBody(
        args: ResolvedArguments,
        settings: WebSearchPluginSettings,
        overrides: SearchPluginControls?
    ) -> [String: Any] {
        let clampedMax = args.maxResults.clamped(to: 0...20)
        let depth = tavilyDepthValue(overrides?.tavilySearchDepth ?? settings.tavilySearchDepth)
        let topic = tavilyTopicValue(overrides?.tavilyTopic ?? settings.tavilyTopic)
        let shouldAutoTune = settings.tavilyAutoParameters
        let hasDepthOverride = overrides?.tavilySearchDepth?.trimmedNonEmpty != nil
        let hasTopicOverride = overrides?.tavilyTopic?.trimmedNonEmpty != nil

        var body: [String: Any] = [
            "query": args.query,
            "max_results": clampedMax
        ]

        if !shouldAutoTune || hasDepthOverride {
            body["search_depth"] = depth
        }

        if !shouldAutoTune || hasTopicOverride {
            body["topic"] = topic
        }

        if let recency = args.recencyDays {
            let calendar = utcGregorianCalendar()
            let now = Date()
            let start = calendar.date(byAdding: .day, value: -recency, to: now) ?? now
            body["start_date"] = tavilyDateString(start)
            body["end_date"] = tavilyDateString(now)
        }

        if !args.includeDomains.isEmpty {
            body["include_domains"] = Array(args.includeDomains.prefix(300))
        }
        if !args.excludeDomains.isEmpty {
            body["exclude_domains"] = Array(args.excludeDomains.prefix(150))
        }

        if args.includeRawContent {
            body["include_raw_content"] = "markdown"
        }

        if topic == "general",
           (!shouldAutoTune || hasTopicOverride),
           let country = tavilyCountryValue(settings.tavilyCountry) {
            body["country"] = country
        }

        if settings.tavilyAutoParameters {
            body["auto_parameters"] = true
        }

        if body["search_depth"] as? String == "advanced" {
            body["chunks_per_source"] = 3
        }

        return body
    }

    nonisolated static func tavilyDepthValue(_ value: String?) -> String {
        guard let depth = value?.trimmedNonEmpty?.lowercased() else { return "basic" }
        let normalized = depth.replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "basic", "fast", "advanced":
            return normalized
        case "ultra_fast":
            return "ultra-fast"
        default:
            return "basic"
        }
    }

    nonisolated static func tavilyTopicValue(_ value: String?) -> String {
        guard let topic = value?.trimmedNonEmpty?.lowercased() else { return "general" }
        switch topic {
        case "general", "news", "finance":
            return topic
        default:
            return "general"
        }
    }

    nonisolated static func tavilyCountryValue(_ value: String?) -> String? {
        guard let raw = value?.trimmedNonEmpty else { return nil }
        let normalized = raw.lowercased()
        if tavilyCountryCodeMap.values.contains(normalized) {
            return normalized
        }

        return tavilyCountryCodeMap[normalized.uppercased()]
    }

    private static let tavilyCountryCodeMap: [String: String] = [
        "AF": "afghanistan", "AL": "albania", "DZ": "algeria", "AD": "andorra",
        "AO": "angola", "AR": "argentina", "AM": "armenia", "AU": "australia",
        "AT": "austria", "AZ": "azerbaijan", "BS": "bahamas", "BH": "bahrain",
        "BD": "bangladesh", "BB": "barbados", "BY": "belarus", "BE": "belgium",
        "BZ": "belize", "BJ": "benin", "BT": "bhutan", "BO": "bolivia",
        "BA": "bosnia and herzegovina", "BW": "botswana", "BR": "brazil", "BN": "brunei",
        "BG": "bulgaria", "BF": "burkina faso", "BI": "burundi", "KH": "cambodia",
        "CM": "cameroon", "CA": "canada", "CV": "cape verde", "CF": "central african republic",
        "TD": "chad", "CL": "chile", "CN": "china", "CO": "colombia",
        "KM": "comoros", "CG": "congo", "CR": "costa rica", "HR": "croatia",
        "CU": "cuba", "CY": "cyprus", "CZ": "czech republic", "DK": "denmark",
        "DJ": "djibouti", "DO": "dominican republic", "EC": "ecuador", "EG": "egypt",
        "SV": "el salvador", "GQ": "equatorial guinea", "ER": "eritrea", "EE": "estonia",
        "ET": "ethiopia", "FJ": "fiji", "FI": "finland", "FR": "france",
        "GA": "gabon", "GM": "gambia", "GE": "georgia", "DE": "germany",
        "GH": "ghana", "GR": "greece", "GT": "guatemala", "GN": "guinea",
        "HT": "haiti", "HN": "honduras", "HU": "hungary", "IS": "iceland",
        "IN": "india", "ID": "indonesia", "IR": "iran", "IQ": "iraq",
        "IE": "ireland", "IL": "israel", "IT": "italy", "JM": "jamaica",
        "JP": "japan", "JO": "jordan", "KZ": "kazakhstan", "KE": "kenya",
        "KW": "kuwait", "KG": "kyrgyzstan", "LV": "latvia", "LB": "lebanon",
        "LS": "lesotho", "LR": "liberia", "LY": "libya", "LI": "liechtenstein",
        "LT": "lithuania", "LU": "luxembourg", "MG": "madagascar", "MW": "malawi",
        "MY": "malaysia", "MV": "maldives", "ML": "mali", "MT": "malta",
        "MR": "mauritania", "MU": "mauritius", "MX": "mexico", "MD": "moldova",
        "MC": "monaco", "MN": "mongolia", "ME": "montenegro", "MA": "morocco",
        "MZ": "mozambique", "MM": "myanmar", "NA": "namibia", "NP": "nepal",
        "NL": "netherlands", "NZ": "new zealand", "NI": "nicaragua", "NE": "niger",
        "NG": "nigeria", "KP": "north korea", "MK": "north macedonia", "NO": "norway",
        "OM": "oman", "PK": "pakistan", "PA": "panama", "PG": "papua new guinea",
        "PY": "paraguay", "PE": "peru", "PH": "philippines", "PL": "poland",
        "PT": "portugal", "QA": "qatar", "RO": "romania", "RU": "russia",
        "RW": "rwanda", "SA": "saudi arabia", "SN": "senegal", "RS": "serbia",
        "SG": "singapore", "SK": "slovakia", "SI": "slovenia", "SO": "somalia",
        "ZA": "south africa", "KR": "south korea", "SS": "south sudan", "ES": "spain",
        "LK": "sri lanka", "SD": "sudan", "SE": "sweden", "CH": "switzerland",
        "SY": "syria", "TW": "taiwan", "TJ": "tajikistan", "TZ": "tanzania",
        "TH": "thailand", "TG": "togo", "TT": "trinidad and tobago", "TN": "tunisia",
        "TR": "turkey", "TM": "turkmenistan", "UG": "uganda", "UA": "ukraine",
        "AE": "united arab emirates", "GB": "united kingdom", "US": "united states",
        "UY": "uruguay", "UZ": "uzbekistan", "VE": "venezuela", "VN": "vietnam",
        "YE": "yemen", "ZM": "zambia", "ZW": "zimbabwe"
    ]

    nonisolated static func tavilyDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated static func utcGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
