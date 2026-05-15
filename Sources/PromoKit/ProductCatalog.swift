import Foundation

struct ProductCatalogEntry: Decodable, Identifiable {
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
    let codesResourceName: String
}

struct ProductCatalog: Decodable {
    let products: [ProductCatalogEntry]
}
