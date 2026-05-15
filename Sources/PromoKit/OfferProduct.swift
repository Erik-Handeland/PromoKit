import Foundation

struct CodeEntry: Codable, Identifiable, Equatable {
    let code: String
    let redeemURL: URL
    var isShared: Bool
    var sharedAt: Date?
    var recipientName: String?

    var id: String { code }

    init(
        code: String,
        redeemURL: URL,
        isShared: Bool = false,
        sharedAt: Date? = nil,
        recipientName: String? = nil
    ) {
        self.code = code
        self.redeemURL = redeemURL
        self.isShared = isShared
        self.sharedAt = sharedAt
        self.recipientName = recipientName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        redeemURL = try container.decode(URL.self, forKey: .redeemURL)
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        sharedAt = try Self.decodeDateIfPresent(from: container, forKey: .sharedAt)
        recipientName = try container.decodeIfPresent(String.self, forKey: .recipientName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(redeemURL, forKey: .redeemURL)
        try container.encode(isShared, forKey: .isShared)

        if let sharedAt {
            try container.encode(Self.stateDateFormatter.string(from: sharedAt), forKey: .sharedAt)
        }

        try container.encodeIfPresent(recipientName, forKey: .recipientName)
    }

    private static let stateDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func decodeDateIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let dateString = try? container.decode(String.self, forKey: key) {
            return stateDateFormatter.date(from: dateString)
        }

        return try? container.decodeIfPresent(Date.self, forKey: key)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case redeemURL
        case isShared
        case sharedAt
        case recipientName
    }
}

struct OfferProduct: Codable, Identifiable, Equatable {
    let id: String
    let appName: String
    let appIconName: String
    let appIconURL: URL?
    let appStoreID: String?
    let appStoreURL: URL?
    let appBundleID: String?
    let productName: String
    let productID: String
    let productType: String
    let status: String
    var customName: String?
    var expiresAt: Date?
    var codes: [CodeEntry]
    let totalCount: Int

    var displayName: String {
        "\(appName) \(displayProductName)"
    }

    var displayProductName: String {
        guard let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return productName
        }

        return customName
    }

    var remainingCodes: [CodeEntry] {
        codes.filter { !$0.isShared }
    }

    var sharedCount: Int {
        codes.filter(\.isShared).count
    }

    var nextCode: CodeEntry? {
        remainingCodes.first
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Calendar.current.startOfDay(for: expiresAt) < Calendar.current.startOfDay(for: Date())
    }

    func shareText(for code: CodeEntry) -> String {
        var lines = [
            "Here is an offer code for \(displayName): \(code.code)"
        ]

        if let expiresAt {
            lines.append("Expires: \(Self.displayDateFormatter.string(from: expiresAt))")
        }

        lines.append("")
        lines.append("Redeem it here:")
        lines.append(code.redeemURL.absoluteString)
        return lines.joined(separator: "\n")
    }

    func exportCSV() -> String {
        let rows = codes.map { code in
            [
                code.code,
                code.redeemURL.absoluteString,
                code.isShared ? "true" : "false",
                code.sharedAt.map(Self.exportDateFormatter.string(from:)) ?? "",
                code.recipientName ?? ""
            ]
            .map(Self.csvEscaped)
            .joined(separator: ",")
        }

        return (["code,redeem_url,is_shared,shared_at,recipient_name"] + rows).joined(separator: "\n")
    }

    init(
        id: String,
        appName: String,
        appIconName: String,
        appIconURL: URL? = nil,
        appStoreID: String? = nil,
        appStoreURL: URL? = nil,
        appBundleID: String? = nil,
        productName: String,
        productID: String,
        productType: String,
        status: String,
        customName: String? = nil,
        expiresAt: Date? = nil,
        codes: [CodeEntry],
        totalCount: Int
    ) {
        self.id = id
        self.appName = appName
        self.appIconName = appIconName
        self.appIconURL = appIconURL
        self.appStoreID = appStoreID
        self.appStoreURL = appStoreURL
        self.appBundleID = appBundleID
        self.productName = productName
        self.productID = productID
        self.productType = productType
        self.status = status
        self.customName = customName
        self.expiresAt = expiresAt
        self.codes = codes
        self.totalCount = totalCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        appIconName = try container.decodeIfPresent(String.self, forKey: .appIconName) ?? "DefaultAppIcon"
        appIconURL = try container.decodeIfPresent(URL.self, forKey: .appIconURL)
        appStoreID = try container.decodeIfPresent(String.self, forKey: .appStoreID)
        appStoreURL = try container.decodeIfPresent(URL.self, forKey: .appStoreURL)
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
        productName = try container.decode(String.self, forKey: .productName)
        productID = try container.decode(String.self, forKey: .productID)
        productType = try container.decode(String.self, forKey: .productType)
        status = try container.decode(String.self, forKey: .status)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        expiresAt = try Self.decodeDateIfPresent(from: container, forKey: .expiresAt)
        codes = try container.decodeIfPresent([CodeEntry].self, forKey: .codes)
            ?? container.decode([CodeEntry].self, forKey: .remainingCodes)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encode(appIconName, forKey: .appIconName)
        try container.encodeIfPresent(appIconURL, forKey: .appIconURL)
        try container.encodeIfPresent(appStoreID, forKey: .appStoreID)
        try container.encodeIfPresent(appStoreURL, forKey: .appStoreURL)
        try container.encodeIfPresent(appBundleID, forKey: .appBundleID)
        try container.encode(productName, forKey: .productName)
        try container.encode(productID, forKey: .productID)
        try container.encode(productType, forKey: .productType)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(customName, forKey: .customName)
        if let expiresAt {
            try container.encode(Self.exportDateFormatter.string(from: expiresAt), forKey: .expiresAt)
        }
        try container.encode(codes, forKey: .codes)
        try container.encode(totalCount, forKey: .totalCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case appName
        case appIconName
        case appIconURL
        case appStoreID
        case appStoreURL
        case appBundleID
        case productName
        case productID
        case productType
        case status
        case customName
        case expiresAt
        case codes
        case remainingCodes
        case totalCount
    }

    private static let exportDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static func decodeDateIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let dateString = try? container.decode(String.self, forKey: key) {
            return exportDateFormatter.date(from: dateString)
        }

        return try? container.decodeIfPresent(Date.self, forKey: key)
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
