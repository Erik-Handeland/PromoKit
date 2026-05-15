import Foundation
import Observation

@MainActor
@Observable
final class CodeStore {
    private let stateDirectoryName = "PromoKit"
    private let stateFileName = "code_inventory_state.json"
    private let legacyStateFileName = "offer_products.json"

    private(set) var products: [OfferProduct] = []
    var loadError: String?

    var totalRemainingCount: Int {
        products.reduce(0) { $0 + $1.remainingCodes.count }
    }

    var totalCodeCount: Int {
        products.reduce(0) { $0 + $1.totalCount }
    }

    var totalSharedCount: Int {
        products.reduce(0) { $0 + $1.sharedCount }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        load()
    }

    init(products: [OfferProduct], loadError: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.products = products
        self.loadError = loadError
    }

    func markShared(_ code: CodeEntry, from product: OfferProduct, recipientName: String? = nil) {
        guard let productIndex = products.firstIndex(where: { $0.id == product.id }),
              let codeIndex = products[productIndex].codes.firstIndex(where: { $0.id == code.id })
        else { return }

        products[productIndex].codes[codeIndex].isShared = true
        products[productIndex].codes[codeIndex].sharedAt = Date()
        if let recipientName = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            products[productIndex].codes[codeIndex].recipientName = recipientName
        }
        saveProducts()
    }

    func markNextCodesShared(count: Int, from product: OfferProduct) {
        guard count > 0,
              let productIndex = products.firstIndex(where: { $0.id == product.id })
        else { return }

        let unsharedIndexes = products[productIndex].codes.indices
            .filter { !products[productIndex].codes[$0].isShared }
            .prefix(count)

        for index in unsharedIndexes {
            products[productIndex].codes[index].isShared = true
            products[productIndex].codes[index].sharedAt = Date()
        }

        saveProducts()
    }

    func updateProduct(_ product: OfferProduct, customName: String?, expiresAt: Date?) {
        guard let productIndex = products.firstIndex(where: { $0.id == product.id }) else { return }

        products[productIndex].customName = customName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        products[productIndex].expiresAt = expiresAt
        saveProducts()
    }

    func importProduct(
        appName: String,
        appIconName: String = "DefaultAppIcon",
        appIconURL: URL? = nil,
        appStoreID: String? = nil,
        appStoreURL: URL? = nil,
        appBundleID: String? = nil,
        productName: String,
        productID: String,
        productType: String,
        status: String,
        codes: [CodeEntry]
    ) {
        let id = uniqueProductID(for: productID.nilIfEmpty ?? productName)
        let product = OfferProduct(
            id: id,
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            appIconName: appIconName,
            appIconURL: appIconURL,
            appStoreID: appStoreID,
            appStoreURL: appStoreURL,
            appBundleID: appBundleID,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            productID: productID.trimmingCharacters(in: .whitespacesAndNewlines),
            productType: productType.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status.trimmingCharacters(in: .whitespacesAndNewlines),
            codes: codes,
            totalCount: codes.count
        )

        products.append(product)
        products.sort { lhs, rhs in
            lhs.appName == rhs.appName ? lhs.productName < rhs.productName : lhs.appName < rhs.appName
        }
        saveProducts()
    }

    func previewImport(from csvContents: String) -> OfferCodeImportPreview {
        let rows = CSVTable.parse(csvContents)
        guard !rows.isEmpty else { return OfferCodeImportPreview() }

        let headers = CSVTable.headerMap(from: rows.first ?? [])
        let hasHeader = headers["code"] != nil
        let dataRows = hasHeader ? Array(rows.dropFirst()) : rows
        let codeIndex = headers["code"] ?? 0
        let redeemURLIndex = headers["redeemurl"] ?? headers["url"] ?? 1
        let existingCodes = Set(products.flatMap { $0.codes.map(\.id) })
        var importedCodes: [CodeEntry] = []
        var seenCodes = Set<String>()
        var skippedDuplicateCount = 0
        var skippedInvalidCount = 0

        for row in dataRows {
            guard let code = row[safe: codeIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let redeemURLString = row[safe: redeemURLIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty,
                  let redeemURL = URL(string: redeemURLString)
            else {
                skippedInvalidCount += 1
                continue
            }

            guard !existingCodes.contains(code), !seenCodes.contains(code) else {
                skippedDuplicateCount += 1
                continue
            }

            seenCodes.insert(code)
            importedCodes.append(CodeEntry(code: code, redeemURL: redeemURL))
        }

        return OfferCodeImportPreview(
            codes: importedCodes,
            metadata: CSVImportMetadata(headers: headers, row: dataRows.first),
            skippedDuplicateCount: skippedDuplicateCount,
            skippedInvalidCount: skippedInvalidCount
        )
    }

    func parseCodes(from csvContents: String) -> [CodeEntry] {
        previewImport(from: csvContents).codes
    }

    func exportCSV(for product: OfferProduct) throws -> URL {
        guard let currentProduct = products.first(where: { $0.id == product.id }) else {
            throw CodeStoreError.missingProduct(product.productName)
        }

        let exportsDirectory = fileManager.temporaryDirectory
            .appending(path: "PromoKitExports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let url = exportsDirectory.appending(path: "\(currentProduct.id)-codes.csv")
        let csv = currentProduct.exportCSV()
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportAllCSV() throws -> URL {
        let exportsDirectory = fileManager.temporaryDirectory
            .appending(path: "PromoKitExports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let url = exportsDirectory.appending(path: "all-codes.csv")
        let csv = allProductsCSV()
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func deleteSavedState() throws {
        for url in try [savedProductsURL(), legacyProductsURL()] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        products = try loadBundledProducts()
        loadError = nil
        saveProducts()
    }

    private func load() {
        do {
            let bundledProducts = try loadBundledProducts()

            if let savedProducts = try loadSavedProducts() {
                products = bundledProducts.mergingSavedState(from: savedProducts)
                saveProducts()
            } else {
                products = bundledProducts
                saveProducts()
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadBundledProducts() throws -> [OfferProduct] {
        let catalog = try loadProductCatalog()

        return try catalog.products.compactMap { entry in
            let codes = try loadBundledCodes(named: entry.codesResourceName)
            guard !codes.isEmpty else { return nil }

            return OfferProduct(
                id: entry.id,
                appName: entry.appName,
                appIconName: entry.appIconName,
                appIconURL: entry.appIconURL,
                appStoreID: entry.appStoreID,
                appStoreURL: entry.appStoreURL,
                appBundleID: entry.appBundleID,
                productName: entry.productName,
                productID: entry.productID,
                productType: entry.productType,
                status: entry.status,
                codes: codes,
                totalCount: codes.count
            )
        }
    }

    private func loadProductCatalog() throws -> ProductCatalog {
        guard let url = Bundle.main.url(forResource: "products", withExtension: "json") else {
            throw CodeStoreError.missingProductCatalog
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProductCatalog.self, from: data)
    }

    private func loadBundledCodes(named resourceName: String) throws -> [CodeEntry] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "csv") else {
            return []
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        return parseCodes(from: contents)
    }

    private func loadSavedProducts() throws -> [OfferProduct]? {
        guard let url = try existingStateURL() else { return nil }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([OfferProduct].self, from: data)
    }

    private func saveProducts() {
        do {
            let url = try savedProductsURL()
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(products)
            try data.write(to: url, options: .atomic)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func savedProductsURL() throws -> URL {
        if let iCloudDocumentsDirectory {
            return iCloudDocumentsDirectory
                .appending(path: stateDirectoryName, directoryHint: .isDirectory)
                .appending(path: stateFileName)
        }

        return try localProductsURL()
    }

    private func existingStateURL() throws -> URL? {
        let currentURL = try savedProductsURL()
        if fileManager.fileExists(atPath: currentURL.path) {
            return currentURL
        }

        let legacyURL = try legacyProductsURL()
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return nil
    }

    private var iCloudDocumentsDirectory: URL? {
        fileManager
            .url(forUbiquityContainerIdentifier: nil)?
            .appending(path: "Documents", directoryHint: .isDirectory)
    }

    private func localProductsURL() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appending(path: stateDirectoryName)
        .appending(path: stateFileName)
    }

    private func legacyProductsURL() throws -> URL {
        if let iCloudDocumentsDirectory {
            return iCloudDocumentsDirectory
                .appending(path: stateDirectoryName, directoryHint: .isDirectory)
                .appending(path: legacyStateFileName)
        }

        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appending(path: stateDirectoryName)
        .appending(path: legacyStateFileName)
    }

    private func allProductsCSV() -> String {
        let rows = products.flatMap { product in
            product.codes.map { code in
                [
                    product.appName,
                    product.appStoreID ?? "",
                    product.appStoreURL?.absoluteString ?? "",
                    product.appBundleID ?? "",
                    product.appIconURL?.absoluteString ?? "",
                    product.productName,
                    product.productID,
                    product.displayProductName,
                    product.productType,
                    product.status,
                    product.expiresAt.map(Self.exportDateFormatter.string(from:)) ?? "",
                    code.code,
                    code.redeemURL.absoluteString,
                    code.isShared ? "true" : "false",
                    code.sharedAt.map(Self.exportDateFormatter.string(from:)) ?? "",
                    code.recipientName ?? ""
                ]
                .map(Self.csvEscaped)
                .joined(separator: ",")
            }
        }

        return ([
            "app_name,app_store_id,app_store_url,app_bundle_id,app_icon_url,product_name,product_id,display_name,product_type,status,expires_at,code,redeem_url,is_shared,shared_at,recipient_name"
        ] + rows).joined(separator: "\n")
    }

    private static let exportDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func uniqueProductID(for seed: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics
        let base = seed
            .lowercased()
            .unicodeScalars
            .map { allowedCharacters.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-")
            .joined(separator: "-")
            .nilIfEmpty ?? UUID().uuidString.lowercased()

        var candidate = base
        var suffix = 2
        while products.contains(where: { $0.id == candidate }) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return candidate
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension [OfferProduct] {
    func mergingSavedState(from savedProducts: [OfferProduct]) -> [OfferProduct] {
        let mergedBundledProducts = map { bundledProduct in
            guard let savedProduct = savedProducts.first(where: { $0.id == bundledProduct.id }) else {
                return bundledProduct
            }

            return OfferProduct(
                id: bundledProduct.id,
                appName: bundledProduct.appName,
                appIconName: bundledProduct.appIconName,
                appIconURL: savedProduct.appIconURL ?? bundledProduct.appIconURL,
                appStoreID: savedProduct.appStoreID ?? bundledProduct.appStoreID,
                appStoreURL: savedProduct.appStoreURL ?? bundledProduct.appStoreURL,
                appBundleID: savedProduct.appBundleID ?? bundledProduct.appBundleID,
                productName: bundledProduct.productName,
                productID: bundledProduct.productID,
                productType: bundledProduct.productType,
                status: bundledProduct.status,
                customName: savedProduct.customName,
                expiresAt: savedProduct.expiresAt,
                codes: bundledProduct.codes.mergingUsageState(from: savedProduct.codes),
                totalCount: bundledProduct.totalCount
            )
        }

        let bundledIDs = Set(map(\.id))
        let importedProducts = savedProducts.filter { !bundledIDs.contains($0.id) }
        return (mergedBundledProducts + importedProducts).sorted { lhs, rhs in
            lhs.appName == rhs.appName ? lhs.productName < rhs.productName : lhs.appName < rhs.appName
        }
    }
}

private extension [CodeEntry] {
    func mergingUsageState(from savedCodes: [CodeEntry]) -> [CodeEntry] {
        let savedCodesByID = Dictionary(uniqueKeysWithValues: savedCodes.map { ($0.id, $0) })

        return map { bundledCode in
            guard let savedCode = savedCodesByID[bundledCode.id] else {
                var sharedCode = bundledCode
                sharedCode.isShared = true
                return sharedCode
            }

            var mergedCode = bundledCode
            mergedCode.isShared = savedCode.isShared
            mergedCode.sharedAt = savedCode.sharedAt
            mergedCode.recipientName = savedCode.recipientName
            return mergedCode
        }
    }
}

enum CodeStoreError: LocalizedError {
    case missingProductCatalog
    case missingBundledCSV(String)
    case missingProduct(String)

    var errorDescription: String? {
        switch self {
        case .missingProductCatalog:
            "The bundled products.json catalog could not be found."
        case .missingBundledCSV(let resourceName):
            "The bundled \(resourceName).csv file could not be found."
        case .missingProduct(let productName):
            "The \(productName) product could not be found."
        }
    }
}

struct OfferCodeImportPreview {
    var codes: [CodeEntry] = []
    var metadata = CSVImportMetadata()
    var skippedDuplicateCount = 0
    var skippedInvalidCount = 0
}

struct CSVImportMetadata {
    var appName: String?
    var appStoreID: String?
    var appStoreURL: String?
    var appBundleID: String?
    var appIconURL: String?
    var productName: String?
    var productID: String?
    var productType: String?
    var status: String?

    init(
        appName: String? = nil,
        appStoreID: String? = nil,
        appStoreURL: String? = nil,
        appBundleID: String? = nil,
        appIconURL: String? = nil,
        productName: String? = nil,
        productID: String? = nil,
        productType: String? = nil,
        status: String? = nil
    ) {
        self.appName = appName
        self.appStoreID = appStoreID
        self.appStoreURL = appStoreURL
        self.appBundleID = appBundleID
        self.appIconURL = appIconURL
        self.productName = productName
        self.productID = productID
        self.productType = productType
        self.status = status
    }

    init(headers: [String: Int], row: [String]?) {
        self.init(
            appName: Self.value(named: "appname", in: row, headers: headers),
            appStoreID: Self.value(named: "appstoreid", in: row, headers: headers),
            appStoreURL: Self.value(named: "appstoreurl", in: row, headers: headers),
            appBundleID: Self.value(named: "appbundleid", in: row, headers: headers),
            appIconURL: Self.value(named: "appiconurl", in: row, headers: headers),
            productName: Self.value(named: "productname", in: row, headers: headers)
                ?? Self.value(named: "displayname", in: row, headers: headers),
            productID: Self.value(named: "productid", in: row, headers: headers),
            productType: Self.value(named: "producttype", in: row, headers: headers),
            status: Self.value(named: "status", in: row, headers: headers)
        )
    }

    private static func value(named name: String, in row: [String]?, headers: [String: Int]) -> String? {
        guard let row,
              let index = headers[name],
              let value = row[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        return value
    }
}

enum CSVTable {
    static func parse(_ contents: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        let characters = Array(contents)
        var index = characters.startIndex

        while index < characters.endIndex {
            let character = characters[index]
            switch character {
            case "\"":
                let nextIndex = characters.index(after: index)
                if isInsideQuotes,
                   nextIndex < characters.endIndex,
                   characters[nextIndex] == "\"" {
                    field.append(character)
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            case "," where !isInsideQuotes:
                row.append(field)
                field = ""
            case "\n" where !isInsideQuotes:
                row.append(field.trimmingCharacters(in: .newlines))
                rows.append(row)
                row = []
                field = ""
            case "\r":
                continue
            default:
                field.append(character)
            }

            index = characters.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    static func headerMap(from row: [String]) -> [String: Int] {
        row.enumerated().reduce(into: [String: Int]()) { result, pair in
            let header = normalizedHeader(pair.element)
            if !header.isEmpty, result[header] == nil {
                result[header] = pair.offset
            }
        }
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
