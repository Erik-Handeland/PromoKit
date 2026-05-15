import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    let store: CodeStore
    @State private var activityRequest: ActivityRequest?
    @AppStorage("overviewMode") private var overviewModeRawValue = OverviewMode.shelf.rawValue

    private var appGroups: [AppProductGroup] {
        Dictionary(grouping: store.products, by: \.appName)
            .map { appName, products in
                AppProductGroup(
                    appName: appName,
                    appIconName: products.first?.appIconName ?? "DefaultAppIcon",
                    appIconURL: products.first?.appIconURL,
                    products: products.sorted { $0.productName < $1.productName }
                )
            }
            .sorted { $0.appName < $1.appName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    DashboardCard(store: store, appCount: appGroups.count)

                    ViewModePicker(selection: overviewModeBinding)

                    if overviewMode == .shelf {
                        ForEach(appGroups) { appGroup in
                            AppGroupView(
                                appGroup: appGroup,
                                shareProduct: shareNextCode,
                                productDestination: productDetailView
                            )
                        }
                    } else {
                        CompactAppsView(
                            appGroups: appGroups,
                            shareProduct: shareNextCode,
                            productDestination: productDetailView
                        )
                    }

                    if let loadError = store.loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .liquidGlassSurface(cornerRadius: 20)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .tint(.primary)
            .navigationTitle("Codes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(
                            store: store,
                            exportAll: exportAll,
                            deleteSavedState: deleteSavedState
                        )
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $activityRequest) { request in
                ActivityView(activityItems: request.activityItems) { completed in
                    request.completion?(completed)
                    activityRequest = nil
                }
            }
        }
    }

    private func productDetailView(for product: OfferProduct) -> some View {
        ProductDetailView(
            product: product,
            share: { code in share(code, from: product) },
            copy: { code in copy(code, from: product) },
            shareQRCode: { code in shareQRCode(code, from: product) },
            shareWithRecipient: { code, recipientName, format in
                share(code, from: product, recipientName: recipientName, format: format)
            },
            export: { export(product) },
            updateProduct: updateProduct,
            markUsed: markCodesUsed
        )
    }

    private var overviewMode: OverviewMode {
        OverviewMode(rawValue: overviewModeRawValue) ?? .shelf
    }

    private var overviewModeBinding: Binding<OverviewMode> {
        Binding(
            get: { overviewMode },
            set: { overviewModeRawValue = $0.rawValue }
        )
    }

    private func exportAll() {
        do {
            let url = try store.exportAllCSV()
            activityRequest = ActivityRequest(activityItems: [url])
        } catch {
            store.loadError = error.localizedDescription
        }
    }

    private func deleteSavedState() {
        do {
            try store.deleteSavedState()
        } catch {
            store.loadError = error.localizedDescription
        }
    }

    private func shareNextCode(from product: OfferProduct) {
        guard let code = product.nextCode else { return }
        share(code, from: product)
    }

    private func share(_ code: CodeEntry, from product: OfferProduct) {
        share(code, from: product, recipientName: nil, format: .text)
    }

    private func share(
        _ code: CodeEntry,
        from product: OfferProduct,
        recipientName: String?,
        format: ShareFormat
    ) {
        switch format {
        case .text:
            shareText(code, from: product, recipientName: recipientName)
        case .qrCard:
            shareQRCode(code, from: product, recipientName: recipientName)
        }
    }

    private func shareText(_ code: CodeEntry, from product: OfferProduct, recipientName: String?) {
        activityRequest = ActivityRequest(activityItems: [product.shareText(for: code)]) { completed in
            if completed {
                store.markShared(code, from: product, recipientName: recipientName)
            }
        }
    }

    private func copy(_ code: CodeEntry, from product: OfferProduct) {
        UIPasteboard.general.string = code.code
        store.markShared(code, from: product)
    }

    private func shareQRCode(_ code: CodeEntry, from product: OfferProduct) {
        shareQRCode(code, from: product, recipientName: nil)
    }

    private func shareQRCode(_ code: CodeEntry, from product: OfferProduct, recipientName: String?) {
        Task {
            let appIcon = await appIconImage(for: product)
            let card = QRShareCardRenderer.makeCard(
                product: product,
                code: code,
                appIcon: appIcon
            )

            await MainActor.run {
                activityRequest = ActivityRequest(activityItems: [card]) { completed in
                    if completed {
                        store.markShared(code, from: product, recipientName: recipientName)
                    }
                }
            }
        }
    }

    private func appIconImage(for product: OfferProduct) async -> UIImage? {
        if let appIconURL = product.appIconURL,
           let (data, _) = try? await URLSession.shared.data(from: appIconURL),
           let image = UIImage(data: data) {
            return image
        }

        return UIImage(named: product.appIconName)
    }

    private func updateProduct(_ product: OfferProduct, customName: String?, expiresAt: Date?) {
        store.updateProduct(product, customName: customName, expiresAt: expiresAt)
    }

    private func markCodesUsed(_ product: OfferProduct, count: Int) {
        store.markNextCodesShared(count: count, from: product)
    }

    private func export(_ product: OfferProduct) {
        do {
            let url = try store.exportCSV(for: product)
            activityRequest = ActivityRequest(activityItems: [url])
        } catch {
            store.loadError = error.localizedDescription
        }
    }
}

private struct AppGroupView<Destination: View>: View {
    let appGroup: AppProductGroup
    let shareProduct: (OfferProduct) -> Void
    let productDestination: (OfferProduct) -> Destination

    private var activeProducts: [OfferProduct] {
        appGroup.products.filter { !$0.isExpired }
    }

    private var expiredProducts: [OfferProduct] {
        appGroup.products.filter(\.isExpired)
    }

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            VStack(spacing: 0) {
                AppSectionHeader(appGroup: appGroup)

                Divider()
                    .padding(.leading, 68)

                ProductRows(
                    products: activeProducts,
                    shareProduct: shareProduct,
                    productDestination: productDestination
                )

                if !expiredProducts.isEmpty {
                    Divider()

                    Text("Expired")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ProductRows(
                        products: expiredProducts,
                        shareProduct: shareProduct,
                        productDestination: productDestination
                    )
                }
            }
            .liquidGlassSurface(cornerRadius: 26)
        }
    }
}

private struct ProductRows<Destination: View>: View {
    let products: [OfferProduct]
    let shareProduct: (OfferProduct) -> Void
    let productDestination: (OfferProduct) -> Destination

    var body: some View {
        VStack(spacing: 0) {
            ForEach(products) { product in
                ProductNavigationRow(
                    product: product,
                    destination: productDestination(product),
                    share: { shareProduct(product) }
                )

                if product.id != products.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }
}

private struct AppProductGroup: Identifiable {
    let appName: String
    let appIconName: String
    let appIconURL: URL?
    let products: [OfferProduct]

    var id: String { appName }

    var remainingCount: Int {
        products.reduce(0) { $0 + $1.remainingCodes.count }
    }

    var totalCount: Int {
        products.reduce(0) { $0 + $1.totalCount }
    }
}

private struct ActivityRequest: Identifiable {
    let id = UUID()
    let activityItems: [Any]
    let completion: ((Bool) -> Void)?

    init(activityItems: [Any], completion: ((Bool) -> Void)? = nil) {
        self.activityItems = activityItems
        self.completion = completion
    }
}

private enum OverviewMode: String, CaseIterable, Identifiable {
    case shelf
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf:
            "Shelf"
        case .compact:
            "Compact"
        }
    }
}

private enum ShareFormat {
    case text
    case qrCard
}

private struct DashboardCard: View {
    let store: CodeStore
    let appCount: Int

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Dashboard")
                        .font(.headline.weight(.semibold))

                    Text("\(appCount) \(appCount == 1 ? "app" : "apps") · \(store.products.count) offers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("\(store.totalSharedCount)/\(store.totalCodeCount)")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()

                    Spacer()

                    Text("\(store.totalRemainingCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: Double(store.totalSharedCount), total: Double(max(store.totalCodeCount, 1)))
                    .tint(.primary)

                HStack(spacing: 10) {
                    DashboardMetric(title: "Available", value: store.totalRemainingCount)
                    DashboardMetric(title: "Shared", value: store.totalSharedCount)
                    DashboardMetric(title: "Total", value: store.totalCodeCount)
                }
            }
            .padding(18)
            .liquidGlassSurface(cornerRadius: 26)
        }
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ViewModePicker: View {
    @Binding var selection: OverviewMode

    var body: some View {
        Picker("View", selection: $selection) {
            ForEach(OverviewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Overview style")
    }
}

private struct CompactAppsView<Destination: View>: View {
    let appGroups: [AppProductGroup]
    let shareProduct: (OfferProduct) -> Void
    let productDestination: (OfferProduct) -> Destination

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            VStack(spacing: 0) {
                ForEach(appGroups) { appGroup in
                    NavigationLink {
                        CompactAppDetailView(
                            appGroup: appGroup,
                            shareProduct: shareProduct,
                            productDestination: productDestination
                        )
                    } label: {
                        CompactAppRow(appGroup: appGroup)
                    }
                    .buttonStyle(.plain)

                    if appGroup.id != appGroups.last?.id {
                        Divider()
                            .padding(.leading, 74)
                    }
                }
            }
            .liquidGlassSurface(cornerRadius: 26)
        }
    }
}

private struct CompactAppRow: View {
    let appGroup: AppProductGroup

    var body: some View {
        HStack(spacing: 14) {
            AppIconImage(name: appGroup.appIconName, url: appGroup.appIconURL, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(appGroup.appName)
                    .font(.headline.weight(.semibold))

                Text("\(appGroup.products.count) offers · \(appGroup.totalCount) codes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(appGroup.remainingCount)")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(.rect)
    }
}

private struct CompactAppDetailView<Destination: View>: View {
    let appGroup: AppProductGroup
    let shareProduct: (OfferProduct) -> Void
    let productDestination: (OfferProduct) -> Destination

    private var activeProducts: [OfferProduct] {
        appGroup.products.filter { !$0.isExpired }
    }

    private var expiredProducts: [OfferProduct] {
        appGroup.products.filter(\.isExpired)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AppSummaryHeader(appGroup: appGroup)

                ProductRows(
                    products: activeProducts,
                    shareProduct: shareProduct,
                    productDestination: productDestination
                )
                .liquidGlassSurface(cornerRadius: 24)

                if !expiredProducts.isEmpty {
                    DetailSection(title: "Expired") {
                        ProductRows(
                            products: expiredProducts,
                            shareProduct: shareProduct,
                            productDestination: productDestination
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(appGroup.appName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppSummaryHeader: View {
    let appGroup: AppProductGroup

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            HStack(spacing: 14) {
                AppIconImage(name: appGroup.appIconName, url: appGroup.appIconURL, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appGroup.appName)
                        .font(.title3.weight(.semibold))

                    Text("\(appGroup.remainingCount) of \(appGroup.totalCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()
            }
            .padding(18)
            .liquidGlassSurface(cornerRadius: 24)
        }
    }
}

private struct AppSectionHeader: View {
    let appGroup: AppProductGroup

    var body: some View {
        HStack(spacing: 10) {
            AppIconImage(name: appGroup.appIconName, url: appGroup.appIconURL, size: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text(appGroup.appName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(appGroup.remainingCount) of \(appGroup.totalCount) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textCase(nil)
            }

            Spacer()
        }
        .padding(16)
        .textCase(nil)
    }
}

private struct ProductNavigationRow<Destination: View>: View {
    let product: OfferProduct
    let destination: Destination
    let share: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                destination
            } label: {
                ProductRow(product: product)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens details")

            Button(action: share) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(.circle)
            }
            .liquidGlassButtonStyle()
            .disabled(product.nextCode == nil || product.isExpired)
            .foregroundStyle(product.nextCode == nil || product.isExpired ? .tertiary : .primary)
            .accessibilityLabel("Share \(product.productName) code")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
    }
}

private struct ProductRow: View {
    let product: OfferProduct

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(product.displayProductName)
                        .font(.headline.weight(.semibold))

                    Spacer()
                }

                Text(product.productID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(product.productType)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let expiresAt = product.expiresAt {
                    Text("Expires \(Self.expiryDateFormatter.string(from: expiresAt))")
                        .font(.caption)
                        .foregroundStyle(product.isExpired ? .red : .secondary)
                }
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(product.remainingCodes.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private static let expiryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct AppIconImage: View {
    let name: String
    var url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Image(name)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct SettingsView: View {
    let store: CodeStore
    let exportAll: () -> Void
    let deleteSavedState: () -> Void
    @State private var isConfirmingDelete = false
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DetailSection(title: "Inventory") {
                    VStack(spacing: 10) {
                        LabeledContent("Apps", value: "\(uniqueAppCount)")
                        LabeledContent("Products", value: "\(store.products.count)")
                        LabeledContent("Remaining", value: "\(store.totalRemainingCount)")
                        LabeledContent("Shared", value: "\(store.totalSharedCount)")
                        LabeledContent("Total", value: "\(store.totalCodeCount)")
                    }
                    .monospacedDigit()
                }

                DetailSection(title: "Appearance") {
                    VStack(spacing: 0) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Button {
                                appAppearanceRawValue = appearance.rawValue
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: appearance.symbolName)
                                        .frame(width: 24)

                                    Text(appearance.title)

                                    Spacer()

                                    if appAppearance == appearance {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                                .foregroundStyle(.primary)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if appearance != AppAppearance.allCases.last {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }

                DetailSection(title: "Manage") {
                    VStack(spacing: 12) {
                        NavigationLink {
                            ImportView(store: store)
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .liquidGlassButtonStyle()
                        .controlSize(.large)

                        Button(action: exportAll) {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .liquidGlassButtonStyle()
                        .controlSize(.large)

                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .liquidGlassButtonStyle()
                        .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete Saved State?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Saved State", role: .destructive, action: deleteSavedState)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shared markers and saved inventory state will be removed.")
        }
    }

    private var uniqueAppCount: Int {
        Set(store.products.map(\.appName)).count
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }
}

private struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    let store: CodeStore
    @State private var appName = ""
    @State private var appStoreURLString = ""
    @State private var appStoreInfo: AppStoreAppInfo?
    @State private var isLookingUpApp = false
    @State private var productName = ""
    @State private var productID = ""
    @State private var productType = ""
    @State private var status = "Approved"
    @State private var parsedCodes: [CodeEntry] = []
    @State private var selectedFileName: String?
    @State private var skippedDuplicateCount = 0
    @State private var skippedInvalidCount = 0
    @State private var isImportingFile = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    isImportingFile = true
                } label: {
                    Label(selectedFileName ?? "Choose CSV", systemImage: "doc.badge.plus")
                }

                if let selectedFileName {
                    LabeledContent("File", value: selectedFileName)
                }

                LabeledContent("Codes", value: "\(parsedCodes.count)")

                if skippedDuplicateCount > 0 {
                    LabeledContent("Duplicates Skipped", value: "\(skippedDuplicateCount)")
                }

                if skippedInvalidCount > 0 {
                    LabeledContent("Rows Skipped", value: "\(skippedInvalidCount)")
                }
            } header: {
                Text("1. CSV")
            } footer: {
                Text("Supports App Store Connect CSV files and exported files from this app.")
            }

            Section("2. App") {
                TextField("App Store URL or ID", text: $appStoreURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button {
                    lookupAppStoreInfo()
                } label: {
                    if isLookingUpApp {
                        Label("Looking Up...", systemImage: "hourglass")
                    } else {
                        Label("Fetch App Info", systemImage: "magnifyingglass")
                    }
                }
                .disabled(appStoreURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUpApp)

                if let appStoreInfo {
                    AppStoreInfoPreview(info: appStoreInfo)
                }

                if !existingAppNames.isEmpty {
                    Menu {
                        ForEach(existingAppNames, id: \.self) { existingAppName in
                            Button(existingAppName) {
                                appName = existingAppName
                            }
                        }
                    } label: {
                        Label("Use Existing App", systemImage: "app.badge")
                    }
                }

                TextField("App name", text: $appName)
                    .textContentType(.organizationName)
            }

            Section("3. Offer") {
                TextField("Offer name", text: $productName)
                TextField("Product ID", text: $productID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Type", text: $productType)
                TextField("Status", text: $status)
            }

            if !parsedCodes.isEmpty {
                Section {
                    LabeledContent("Ready to Import", value: "\(parsedCodes.count)")
                    LabeledContent("First Code", value: redactedCode(parsedCodes[0].code))
                    if parsedCodes.count > 1 {
                        LabeledContent("Last Code", value: redactedCode(parsedCodes[parsedCodes.count - 1].code))
                    }
                } header: {
                    Text("Review")
                } footer: {
                    Text("Codes are hidden by default after import; sharing or copying marks a code as used.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.importProduct(
                        appName: appName,
                        appIconURL: appStoreInfo?.iconURL,
                        appStoreID: appStoreInfo?.appStoreID,
                        appStoreURL: appStoreInfo?.appStoreURL,
                        appBundleID: appStoreInfo?.bundleID,
                        productName: productName,
                        productID: productID,
                        productType: productType,
                        status: status,
                        codes: parsedCodes
                    )
                    dismiss()
                }
                .disabled(!canImport)
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.commaSeparatedText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private var canImport: Bool {
        !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !productType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !parsedCodes.isEmpty
    }

    private var existingAppNames: [String] {
        Array(Set(store.products.map(\.appName))).sorted()
    }

    private func lookupAppStoreInfo() {
        isLookingUpApp = true
        errorMessage = nil

        Task {
            do {
                let info = try await AppStoreLookupService.lookup(from: appStoreURLString)
                await MainActor.run {
                    appStoreInfo = info
                    appStoreURLString = info.appStoreURL.absoluteString
                    appName = info.appName
                    isLookingUpApp = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLookingUpApp = false
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let contents = try String(contentsOf: url, encoding: .utf8)
            let preview = store.previewImport(from: contents)
            guard !preview.codes.isEmpty else {
                errorMessage = "No offer codes were found in that CSV."
                parsedCodes = []
                selectedFileName = url.lastPathComponent
                skippedDuplicateCount = preview.skippedDuplicateCount
                skippedInvalidCount = preview.skippedInvalidCount
                return
            }

            parsedCodes = preview.codes
            selectedFileName = url.lastPathComponent
            skippedDuplicateCount = preview.skippedDuplicateCount
            skippedInvalidCount = preview.skippedInvalidCount
            apply(metadata: preview.metadata)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(metadata: CSVImportMetadata) {
        if appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let metadataAppName = metadata.appName {
            appName = metadataAppName
        }

        if appStoreURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let metadataAppStoreURL = metadata.appStoreURL {
            appStoreURLString = metadataAppStoreURL
        }

        if appStoreInfo == nil,
           let metadataAppName = metadata.appName,
           let metadataAppStoreID = metadata.appStoreID,
           let metadataAppStoreURL = metadata.appStoreURL,
           let metadataAppStoreURLValue = URL(string: metadataAppStoreURL),
           let metadataBundleID = metadata.appBundleID {
            appStoreInfo = AppStoreAppInfo(
                appStoreID: metadataAppStoreID,
                appName: metadataAppName,
                bundleID: metadataBundleID,
                appStoreURL: metadataAppStoreURLValue,
                iconURL: metadata.appIconURL.flatMap(URL.init(string:))
            )
        }

        if productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let metadataProductName = metadata.productName {
            productName = metadataProductName
        }

        if productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let metadataProductID = metadata.productID {
            productID = metadataProductID
        }

        if productType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let metadataProductType = metadata.productType {
            productType = metadataProductType
        }

        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let metadataStatus = metadata.status {
            status = metadataStatus
        }
    }

    private func redactedCode(_ code: String) -> String {
        guard code.count > 8 else { return "••••" }
        return "\(code.prefix(4))••••\(code.suffix(4))"
    }
}

private struct AppStoreInfoPreview: View {
    let info: AppStoreAppInfo

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: info.iconURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "app")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.appName)
                    .font(.subheadline.weight(.semibold))

                Text(info.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

private struct ProductDetailView: View {
    let product: OfferProduct
    let share: (CodeEntry) -> Void
    let copy: (CodeEntry) -> Void
    let shareQRCode: (CodeEntry) -> Void
    let shareWithRecipient: (CodeEntry, String?, ShareFormat) -> Void
    let export: () -> Void
    let updateProduct: (OfferProduct, String?, Date?) -> Void
    let markUsed: (OfferProduct, Int) -> Void
    @State private var sheet: ProductDetailSheet?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LiquidGlassContainer(spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            AppIconImage(name: product.appIconName, url: product.appIconURL, size: 52)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.appName)
                                    .font(.headline)

                                Text(product.displayProductName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("\(product.sharedCount)/\(product.totalCount)")
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                                .monospacedDigit()

                            Spacer()

                            Text("\(product.remainingCodes.count) remaining")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        ProgressView(
                            value: Double(product.sharedCount),
                            total: Double(max(product.totalCount, 1))
                        )
                        .tint(.primary)

                        if product.isExpired {
                            Label("Expired", systemImage: "calendar.badge.exclamationmark")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else if let nextCode = product.nextCode {
                            HStack(spacing: 12) {
                                Button {
                                    copy(nextCode)
                                } label: {
                                    Label("Copy Code", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .liquidGlassButtonStyle(prominent: true)

                                Button {
                                    share(nextCode)
                                } label: {
                                    Label("Share Code", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .liquidGlassButtonStyle()
                            }
                            .controlSize(.large)
                        } else {
                            Label("No Codes Remaining", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Details", systemImage: "doc.text")
                                .font(.subheadline.weight(.medium))

                            LabeledContent("Product ID", value: product.productID)
                            LabeledContent("Type", value: product.productType)
                            LabeledContent("Status", value: product.status)
                            if let expiresAt = product.expiresAt {
                                LabeledContent("Expires", value: Self.expiryDateFormatter.string(from: expiresAt))
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding(16)
                    .liquidGlassSurface(cornerRadius: 24)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(product.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sheet = .edit
                    } label: {
                        Label("Edit Offer", systemImage: "pencil")
                    }

                    Button {
                        sheet = .markUsed
                    } label: {
                        Label("Mark Used", systemImage: "checkmark.circle")
                    }
                    .disabled(product.remainingCodes.isEmpty)

                    if let nextCode = product.nextCode {
                        Button {
                            sheet = .shareWithName
                        } label: {
                            Label("Share With Name", systemImage: "person.text.rectangle")
                        }
                        .disabled(product.isExpired)

                        Button {
                            shareQRCode(nextCode)
                        } label: {
                            Label("Share QR Card", systemImage: "qrcode")
                        }
                        .disabled(product.isExpired)
                    }

                    Button(action: export) {
                        Label("Export CSV", systemImage: "doc.badge.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit:
                ProductEditSheet(product: product) { customName, expiresAt in
                    updateProduct(product, customName, expiresAt)
                }
            case .markUsed:
                BulkMarkUsedSheet(product: product) { count in
                    markUsed(product, count)
                }
            case .shareWithName:
                if let nextCode = product.nextCode {
                    RecipientShareSheet(product: product) { recipientName, format in
                        shareWithRecipient(nextCode, recipientName, format)
                    }
                }
            }
        }
    }

    private static let expiryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private enum ProductDetailSheet: String, Identifiable {
    case edit
    case markUsed
    case shareWithName

    var id: String { rawValue }
}

private struct ProductEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let product: OfferProduct
    let save: (String?, Date?) -> Void
    @State private var name: String
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date

    init(product: OfferProduct, save: @escaping (String?, Date?) -> Void) {
        self.product = product
        self.save = save
        _name = State(initialValue: product.displayProductName)
        _hasExpiry = State(initialValue: product.expiresAt != nil)
        _expiresAt = State(initialValue: product.expiresAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Offer") {
                    TextField("Name", text: $name)

                    Toggle("Expiry Date", isOn: $hasExpiry)

                    if hasExpiry {
                        DatePicker(
                            "Expires",
                            selection: $expiresAt,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle("Edit Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        save(trimmedName == product.productName ? nil : trimmedName, hasExpiry ? expiresAt : nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BulkMarkUsedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let product: OfferProduct
    let markUsed: (Int) -> Void
    @State private var count = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $count, in: 1...max(product.remainingCodes.count, 1)) {
                        LabeledContent("Codes", value: "\(count)")
                    }
                } footer: {
                    Text("\(product.remainingCodes.count) remaining")
                }
            }
            .navigationTitle("Mark Used")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Used") {
                        markUsed(count)
                        dismiss()
                    }
                    .disabled(product.remainingCodes.isEmpty)
                }
            }
        }
    }
}

private struct RecipientShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let product: OfferProduct
    let share: (String?, ShareFormat) -> Void
    @State private var recipientName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipient name", text: $recipientName)
                        .textContentType(.name)
                } footer: {
                    Text("The name is saved with the code and included when you export CSV.")
                }

                Section {
                    Button {
                        share(trimmedRecipientName, .text)
                        dismiss()
                    } label: {
                        Label("Share Code", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        share(trimmedRecipientName, .qrCard)
                        dismiss()
                    } label: {
                        Label("Share QR Card", systemImage: "qrcode")
                    }
                }
            }
            .navigationTitle(product.displayProductName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var trimmedRecipientName: String? {
        let trimmedName = recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        LiquidGlassContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                content
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlassSurface(cornerRadius: 22)
        }
    }
}

private struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct LiquidGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct LiquidGlassButtonStyleModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content
                    .tint(.primary)
                    .buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content
                .tint(.primary)
                .buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private extension View {
    func liquidGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, interactive: interactive))
    }

    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonStyleModifier(prominent: prominent))
    }
}

#Preview {
    ContentView(store: CodeStore(products: [.previewAnnual, .previewLifetime]))
}

#Preview("Load Error") {
    ContentView(
        store: CodeStore(
            products: [.previewAnnual],
            loadError: "The bundled products.json catalog could not be found."
        )
    )
}

private extension OfferProduct {
    static let previewAnnual = OfferProduct(
        id: "sample-yearly",
        appName: "Sample App",
        appIconName: "DefaultAppIcon",
        productName: "Yearly",
        productID: "com.example.sample.yearly",
        productType: "1 year",
        status: "Approved",
        codes: CodeEntry.previewCodes(count: 4),
        totalCount: 4
    )

    static let previewLifetime = OfferProduct(
        id: "sample-lifetime",
        appName: "Sample App",
        appIconName: "DefaultAppIcon",
        productName: "Lifetime",
        productID: "com.example.sample.lifetime",
        productType: "Non-Consumable",
        status: "Approved",
        codes: CodeEntry.previewCodes(count: 4, sharedCount: 1),
        totalCount: 4
    )
}

private extension CodeEntry {
    static func previewCodes(count: Int, sharedCount: Int = 0) -> [CodeEntry] {
        (1...count).map { index in
            CodeEntry(
                code: "preview-code-\(index)",
                redeemURL: URL(string: "https://example.com/redeem/preview-code-\(index)")!,
                isShared: index <= sharedCount,
                sharedAt: index <= sharedCount ? Date(timeIntervalSince1970: 1_800_000_000) : nil
            )
        }
    }
}
