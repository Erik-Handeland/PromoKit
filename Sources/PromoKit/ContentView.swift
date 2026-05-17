import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    let store: CodeStore
    @State private var presentedSheet: PresentedSheet?
    @AppStorage("overviewMode") private var overviewModeRawValue = OverviewMode.shelf.rawValue

    private var appGroups: [AppProductGroup] {
        store.apps.map { app in
            let products = store.products.filter { $0.appName == app.name }
            return AppProductGroup(
                app: app,
                products: products.sorted { $0.productName < $1.productName }
            )
        }
        .sorted { $0.app.name < $1.app.name }
    }

    private var appCount: Int {
        store.apps.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    DashboardCard(store: store, appCount: appCount)

                    if appGroups.isEmpty {
                        AddAppRow {
                            presentedSheet = .addApp
                        }
                    } else {
                        if overviewMode == .shelf {
                            ForEach(appGroups) { appGroup in
                                AppGroupView(
                                    appGroup: appGroup,
                                    addOffer: { presentedSheet = .addOffer(appGroup.app) },
                                    exportApp: exportApp,
                                    deleteApp: deleteApp,
                                    shareProduct: shareNextCode,
                                    openProduct: { presentedSheet = .productDetail($0) }
                                )
                            }
                        } else {
                            CompactAppsView(
                                appGroups: appGroups,
                                addOffer: { presentedSheet = .addOffer($0) },
                                exportApp: exportApp,
                                deleteApp: deleteApp,
                                shareProduct: shareNextCode,
                                openApp: { presentedSheet = .appDetail($0.app) }
                            )
                        }
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
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        presentedSheet = .addApp
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add App")

                    NavigationLink {
                        SettingsView(
                            store: store,
                            overviewMode: overviewModeBinding,
                            exportAll: exportAll,
                            deleteSavedState: deleteSavedState
                        )
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .addApp:
                    NavigationStack {
                        AddAppView(store: store)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                case .addOffer(let app):
                    NavigationStack {
                        ImportView(store: store, selectedApp: app)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                case .appDetail(let app):
                    if let appGroup = appGroup(for: app) {
                        NavigationStack {
                            AppDetailSheetView(
                                appGroup: appGroup,
                                addOffer: { presentedSheet = .addOffer(appGroup.app) },
                                exportApp: { exportApp(appGroup.app) },
                                deleteApp: {
                                    deleteApp(appGroup.app)
                                    presentedSheet = nil
                                },
                                shareProduct: shareNextCode,
                                openProduct: { presentedSheet = .productDetail($0) }
                            )
                        }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                case .productDetail(let product):
                    NavigationStack {
                        productDetailView(for: product)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                case .activity(let request):
                    ActivityView(activityItems: request.activityItems) { completed in
                        request.completion?(completed)
                        presentedSheet = nil
                    }
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
            export: { export(product) },
            updateProduct: updateProduct,
            deleteProduct: {
                deleteProduct($0)
                presentedSheet = nil
            },
            markUsed: markCodesUsed
        )
    }

    private func appGroup(for app: TrackedApp) -> AppProductGroup? {
        appGroups.first { $0.app.id == app.id || $0.app.name.caseInsensitiveCompare(app.name) == .orderedSame }
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
            presentedSheet = .activity(ActivityRequest(activityItems: [url]))
        } catch {
            store.loadError = error.localizedDescription
        }
    }

    private func exportApp(_ app: TrackedApp) {
        do {
            let url = try store.exportCSV(for: app)
            presentedSheet = .activity(ActivityRequest(activityItems: [url]))
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

    private func deleteApp(_ app: TrackedApp) {
        store.deleteApp(app)
    }

    private func shareNextCode(from product: OfferProduct) {
        guard let code = product.nextCode else { return }
        share(code, from: product)
    }

    private func share(_ code: CodeEntry, from product: OfferProduct) {
        shareText(code, from: product)
    }

    private func shareText(_ code: CodeEntry, from product: OfferProduct) {
        presentedSheet = .activity(ActivityRequest(activityItems: [product.shareText(for: code)]) { completed in
            if completed {
                store.markShared(code, from: product)
            }
        })
    }

    private func copy(_ code: CodeEntry, from product: OfferProduct) {
        UIPasteboard.general.string = code.code
        store.markShared(code, from: product)
    }

    private func shareQRCode(_ code: CodeEntry, from product: OfferProduct) {
        Task {
            let appIcon = await appIconImage(for: product)
            let card = QRShareCardRenderer.makeCard(
                product: product,
                code: code,
                appIcon: appIcon
            )

            await MainActor.run {
                presentedSheet = .activity(ActivityRequest(activityItems: [card]) { completed in
                    if completed {
                        store.markShared(code, from: product)
                    }
                })
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

    private func updateProduct(_ product: OfferProduct, customName: String?, productType: String, expiresAt: Date?) {
        store.updateProduct(product, customName: customName, productType: productType, expiresAt: expiresAt)
    }

    private func deleteProduct(_ product: OfferProduct) {
        store.deleteProduct(product)
    }

    private func markCodesUsed(_ product: OfferProduct, count: Int) {
        store.markNextCodesShared(count: count, from: product)
    }

    private func export(_ product: OfferProduct) {
        do {
            let url = try store.exportCSV(for: product)
            presentedSheet = .activity(ActivityRequest(activityItems: [url]))
        } catch {
            store.loadError = error.localizedDescription
        }
    }
}

private struct AppGroupView: View {
    let appGroup: AppProductGroup
    let addOffer: () -> Void
    let exportApp: (TrackedApp) -> Void
    let deleteApp: (TrackedApp) -> Void
    let shareProduct: (OfferProduct) -> Void
    let openProduct: (OfferProduct) -> Void
    @State private var isConfirmingDelete = false

    private var activeProducts: [OfferProduct] {
        appGroup.products.filter { !$0.isExpired }
    }

    private var expiredProducts: [OfferProduct] {
        appGroup.products.filter(\.isExpired)
    }

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            VStack(spacing: 0) {
                AppSectionHeader(
                    appGroup: appGroup,
                    addOffer: addOffer,
                    exportApp: { exportApp(appGroup.app) },
                    deleteApp: { isConfirmingDelete = true }
                )

                Divider()
                    .padding(.leading, 68)

                ProductRows(
                    products: activeProducts,
                    shareProduct: shareProduct,
                    openProduct: openProduct
                )

                if appGroup.totalCount == 0 {
                    AddCodesRow(action: addOffer)
                        .padding(.top, activeProducts.isEmpty ? 0 : 8)
                }

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
                        openProduct: openProduct
                    )
                }
            }
            .liquidGlassSurface(cornerRadius: 26)
        }
        .confirmationDialog("Delete \(appGroup.appName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete App", role: .destructive) {
                deleteApp(appGroup.app)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the app and all offers and codes saved for it.")
        }
    }
}

private struct ProductRows: View {
    let products: [OfferProduct]
    let shareProduct: (OfferProduct) -> Void
    let openProduct: (OfferProduct) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(products) { product in
                ProductNavigationRow(
                    product: product,
                    open: { openProduct(product) },
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
    let app: TrackedApp
    let products: [OfferProduct]

    var id: String { app.id }
    var appName: String { app.name }
    var appIconName: String {
        if app.iconName != "DefaultAppIcon" {
            return app.iconName
        }

        return products.first { $0.appIconName != "DefaultAppIcon" }?.appIconName ?? app.iconName
    }

    var appIconURL: URL? {
        app.iconURL ?? products.first(where: { $0.appIconURL != nil })?.appIconURL
    }

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

private enum PresentedSheet: Identifiable {
    case addApp
    case addOffer(TrackedApp)
    case appDetail(TrackedApp)
    case productDetail(OfferProduct)
    case activity(ActivityRequest)

    var id: String {
        switch self {
        case .addApp:
            "addApp"
        case .addOffer(let app):
            "addOffer-\(app.id)"
        case .appDetail(let app):
            "appDetail-\(app.id)"
        case .productDetail(let product):
            "productDetail-\(product.id)"
        case .activity(let request):
            request.id.uuidString
        }
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

private struct AddAppRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add App")
                        .font(.headline.weight(.semibold))

                    Text("Import codes for an app or offer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .contentShape(.rect)
            .liquidGlassSurface(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add App Row")
    }
}

private struct AddCodesRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Codes")
                        .font(.subheadline.weight(.semibold))

                    Text("Create an offer or import a CSV.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Codes")
    }
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

private struct CompactAppsView: View {
    let appGroups: [AppProductGroup]
    let addOffer: (TrackedApp) -> Void
    let exportApp: (TrackedApp) -> Void
    let deleteApp: (TrackedApp) -> Void
    let shareProduct: (OfferProduct) -> Void
    let openApp: (AppProductGroup) -> Void
    @State private var appPendingDeletion: TrackedApp?

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            VStack(spacing: 0) {
                ForEach(appGroups) { appGroup in
                    Button {
                        openApp(appGroup)
                    } label: {
                        CompactAppRow(appGroup: appGroup)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            addOffer(appGroup.app)
                        } label: {
                            Label("Add Codes", systemImage: "doc.badge.plus")
                        }

                        Button {
                            exportApp(appGroup.app)
                        } label: {
                            Label("Export App", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            appPendingDeletion = appGroup.app
                        } label: {
                            Label("Delete App", systemImage: "trash")
                        }
                    }

                    if appGroup.id != appGroups.last?.id {
                        Divider()
                            .padding(.leading, 74)
                    }
                }
            }
            .liquidGlassSurface(cornerRadius: 26)
        }
        .confirmationDialog(
            "Delete \(appPendingDeletion?.name ?? "App")?",
            isPresented: isDeletingApp,
            titleVisibility: .visible
        ) {
            Button("Delete App", role: .destructive) {
                if let appPendingDeletion {
                    deleteApp(appPendingDeletion)
                }
                appPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                appPendingDeletion = nil
            }
        } message: {
            Text("This removes the app and all offers and codes saved for it.")
        }
    }

    private var isDeletingApp: Binding<Bool> {
        Binding {
            appPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                appPendingDeletion = nil
            }
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

private struct AppDetailSheetView: View {
    let appGroup: AppProductGroup
    let addOffer: () -> Void
    let exportApp: () -> Void
    let deleteApp: () -> Void
    let shareProduct: (OfferProduct) -> Void
    let openProduct: (OfferProduct) -> Void
    @State private var isConfirmingDelete = false

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
                    openProduct: openProduct
                )
                .liquidGlassSurface(cornerRadius: 24)

                if appGroup.totalCount == 0 {
                    AddCodesRow(action: addOffer)
                        .liquidGlassSurface(cornerRadius: 22)
                }

                if !expiredProducts.isEmpty {
                    DetailSection(title: "Expired") {
                        ProductRows(
                            products: expiredProducts,
                            shareProduct: shareProduct,
                            openProduct: openProduct
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: addOffer) {
                        Label("Add Codes", systemImage: "doc.badge.plus")
                    }

                    Button(action: exportApp) {
                        Label("Export App", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete App", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("App Actions")
            }
        }
        .confirmationDialog("Delete \(appGroup.appName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete App", role: .destructive, action: deleteApp)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the app and all offers and codes saved for it.")
        }
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
    let addOffer: () -> Void
    let exportApp: () -> Void
    let deleteApp: () -> Void

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

            Menu {
                Button(action: addOffer) {
                    Label("Add Codes", systemImage: "doc.badge.plus")
                }

                Button(action: exportApp) {
                    Label("Export App", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive, action: deleteApp) {
                    Label("Delete App", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("App Actions")
        }
        .padding(16)
        .textCase(nil)
    }
}

private struct ProductNavigationRow: View {
    let product: OfferProduct
    let open: () -> Void
    let share: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                ProductRow(product: product)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens details")

            Button(action: share) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(product.nextCode == nil || product.isExpired)
            .foregroundStyle(product.nextCode == nil || product.isExpired ? Color.secondary.opacity(0.4) : Color.primary)
            .accessibilityLabel("Share \(product.productName) code")
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
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
    @Binding var overviewMode: OverviewMode
    let exportAll: () -> Void
    let deleteSavedState: () -> Void
    @State private var isConfirmingDelete = false
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appAppearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }

                Toggle("Compact Layout", isOn: compactLayoutBinding)
            }

            Section {
                Button(action: exportAll) {
                    Text("Export")
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text("Delete Saved State")
                }
            } footer: {
                Text("\(store.totalRemainingCount) remaining · \(store.totalSharedCount) shared")
                    .monospacedDigit()
            }
        }
        .scrollContentBackground(.hidden)
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

    private var compactLayoutBinding: Binding<Bool> {
        Binding(
            get: { overviewMode == .compact },
            set: { overviewMode = $0 ? .compact : .shelf }
        )
    }

}

private struct AddAppView: View {
    @Environment(\.dismiss) private var dismiss
    let store: CodeStore
    @State private var appName = ""
    @State private var appSearchQuery = ""
    @State private var appSearchResults: [AppStoreAppInfo] = []
    @State private var appStoreURLString = ""
    @State private var appStoreInfo: AppStoreAppInfo?
    @State private var isSearchingAppStore = false
    @State private var isLookingUpApp = false
    @State private var isShowingManual = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                AppStoreSearchField(
                    query: $appSearchQuery,
                    isSearching: isSearchingAppStore,
                    search: searchAppStore
                )

                if !appSearchResults.isEmpty {
                    AppStoreSearchResultsList(
                        results: appSearchResults,
                        selectedApp: appStoreInfo,
                        select: apply
                    )
                }

                if let appStoreInfo, appSearchResults.isEmpty {
                    AppStoreInfoPreview(info: appStoreInfo, showsSelection: true)
                }

                DisclosureGroup(isExpanded: $isShowingManual.animation()) {
                    TextField("App name", text: $appName)
                        .textContentType(.organizationName)

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
                } label: {
                    Label("Manual", systemImage: "keyboard")
                }
            } header: {
                Text("App")
            } footer: {
                Text("Add the app first. Offers and code CSVs are added from the app card.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add App")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.addApp(
                        name: resolvedAppName,
                        iconURL: appStoreInfo?.iconURL,
                        appStoreID: appStoreInfo?.appStoreID,
                        appStoreURL: appStoreInfo?.appStoreURL,
                        bundleID: appStoreInfo?.bundleID
                    )
                    dismiss()
                }
                .disabled(resolvedAppName.isEmpty)
            }
        }
    }

    private var resolvedAppName: String {
        let trimmedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAppName.isEmpty {
            return trimmedAppName
        }

        return (appStoreInfo?.appName ?? appSearchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchAppStore() {
        isSearchingAppStore = true
        errorMessage = nil

        Task {
            do {
                let results = try await AppStoreLookupService.search(for: appSearchQuery)
                await MainActor.run {
                    appSearchResults = results
                    isSearchingAppStore = false
                    if results.isEmpty {
                        errorMessage = "No App Store apps matched that search."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearchingAppStore = false
                }
            }
        }
    }

    private func lookupAppStoreInfo() {
        isLookingUpApp = true
        errorMessage = nil

        Task {
            do {
                let info = try await AppStoreLookupService.lookup(from: appStoreURLString)
                await MainActor.run {
                    apply(appInfo: info)
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

    private func apply(appInfo: AppStoreAppInfo) {
        appStoreInfo = appInfo
        appStoreURLString = appInfo.appStoreURL.absoluteString
        appSearchQuery = appInfo.appName
        appSearchResults = []
        appName = appInfo.appName
        errorMessage = nil
    }
}

private struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    let store: CodeStore
    let selectedApp: TrackedApp?
    @State private var appName = ""
    @State private var appSearchQuery = ""
    @State private var appSearchResults: [AppStoreAppInfo] = []
    @State private var appStoreURLString = ""
    @State private var appStoreInfo: AppStoreAppInfo?
    @State private var isSearchingAppStore = false
    @State private var isLookingUpApp = false
    @State private var productName = ""
    @State private var productID = ""
    @State private var offerKind = OfferKind.iap
    @State private var hasExpiry = false
    @State private var expiresAt = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var parsedCodes: [CodeEntry] = []
    @State private var selectedFileName: String?
    @State private var skippedDuplicateCount = 0
    @State private var skippedInvalidCount = 0
    @State private var isImportingFile = false
    @State private var isShowingManual = false
    @State private var errorMessage: String?

    init(store: CodeStore, selectedApp: TrackedApp? = nil) {
        self.store = store
        self.selectedApp = selectedApp
        _appName = State(initialValue: selectedApp?.name ?? "")
        _appStoreURLString = State(initialValue: selectedApp?.appStoreURL?.absoluteString ?? "")
    }

    var body: some View {
        Form {
            Section {
                if let selectedApp {
                    HStack(spacing: 12) {
                        AppIconImage(name: selectedApp.iconName, url: selectedApp.iconURL, size: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedApp.name)
                                .font(.headline.weight(.semibold))
                            Text("Adding codes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                AppStoreSearchField(
                    query: $appSearchQuery,
                    isSearching: isSearchingAppStore,
                    search: searchAppStore
                )

                if !appSearchResults.isEmpty {
                    AppStoreSearchResultsList(
                        results: appSearchResults,
                        selectedApp: appStoreInfo,
                        select: apply
                    )
                }

                if let appStoreInfo, appSearchResults.isEmpty {
                    AppStoreInfoPreview(info: appStoreInfo, showsSelection: true)
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

                DisclosureGroup(isExpanded: $isShowingManual.animation()) {
                    TextField("App name", text: $appName)
                        .textContentType(.organizationName)

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
                } label: {
                    Label("Manual", systemImage: "keyboard")
                }
                }
            } header: {
                Text("App")
            } footer: {
                Text(selectedApp == nil ? "Choose the app these codes belong to." : "Offers and codes will be added to this app.")
            }

            Section("Offer") {
                TextField("Offer name", text: $productName)
                TextField("Product ID", text: $productID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                OfferKindSelection(selection: $offerKind)

                ExpirationPicker(hasExpiry: $hasExpiry, expiresAt: $expiresAt)
            }

            Section {
                Button {
                    isImportingFile = true
                } label: {
                    Label(selectedFileName ?? "Choose CSV", systemImage: "doc.badge.plus")
                }

                LabeledContent("Codes", value: "\(parsedCodes.count)")

                if let selectedFileName {
                    LabeledContent("File", value: selectedFileName)
                }

                if skippedDuplicateCount > 0 {
                    LabeledContent("Duplicates Skipped", value: "\(skippedDuplicateCount)")
                }

                if skippedInvalidCount > 0 {
                    LabeledContent("Rows Skipped", value: "\(skippedInvalidCount)")
                }
            } header: {
                Text("CSV")
            } footer: {
                Text("Optional. Supports App Store Connect CSV files and PromoKit exports. Codes stay hidden after import.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Codes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.importProduct(
                        appName: resolvedAppName,
                        appIconName: selectedApp?.iconName ?? "DefaultAppIcon",
                        appIconURL: selectedApp?.iconURL ?? appStoreInfo?.iconURL,
                        appStoreID: selectedApp?.appStoreID ?? appStoreInfo?.appStoreID,
                        appStoreURL: selectedApp?.appStoreURL ?? appStoreInfo?.appStoreURL,
                        appBundleID: selectedApp?.bundleID ?? appStoreInfo?.bundleID,
                        productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
                        productID: resolvedProductID,
                        productType: offerKind.title,
                        expiresAt: hasExpiry ? expiresAt : nil,
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
        !resolvedAppName.isEmpty &&
            !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedAppName: String {
        let trimmedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAppName.isEmpty {
            return trimmedAppName
        }

        return (appStoreInfo?.appName ?? appSearchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedProductID: String {
        let trimmedProductID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProductID.isEmpty {
            return trimmedProductID
        }

        return productName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private var existingAppNames: [String] {
        store.apps.map(\.name).sorted()
    }

    private func searchAppStore() {
        isSearchingAppStore = true
        errorMessage = nil

        Task {
            do {
                let results = try await AppStoreLookupService.search(for: appSearchQuery)
                await MainActor.run {
                    appSearchResults = results
                    isSearchingAppStore = false
                    if results.isEmpty {
                        errorMessage = "No App Store apps matched that search."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearchingAppStore = false
                }
            }
        }
    }

    private func lookupAppStoreInfo() {
        isLookingUpApp = true
        errorMessage = nil

        Task {
            do {
                let info = try await AppStoreLookupService.lookup(from: appStoreURLString)
                await MainActor.run {
                    apply(appInfo: info)
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

    private func apply(appInfo: AppStoreAppInfo) {
        appStoreInfo = appInfo
        appStoreURLString = appInfo.appStoreURL.absoluteString
        appSearchQuery = appInfo.appName
        appSearchResults = []
        appName = appInfo.appName
        errorMessage = nil
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

        if let metadataProductType = metadata.productType,
           let metadataOfferKind = OfferKind(productType: metadataProductType) {
            offerKind = metadataOfferKind
        }

        if let metadataExpiresAt = metadata.expiresAt,
           let metadataExpiryDate = Self.expiryDate(from: metadataExpiresAt) {
            expiresAt = metadataExpiryDate
            hasExpiry = true
        }
    }

    private static func expiryDate(from value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: value) {
            return date
        }

        let mediumFormatter = DateFormatter()
        mediumFormatter.dateStyle = .medium
        mediumFormatter.timeStyle = .none
        return mediumFormatter.date(from: value)
    }

}

private enum OfferKind: String, CaseIterable, Identifiable {
    case iap
    case subscriptionOneWeek
    case subscriptionOneMonth
    case subscriptionOneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iap:
            "IAP"
        case .subscriptionOneWeek:
            "Subscription 1w"
        case .subscriptionOneMonth:
            "Subscription 1m"
        case .subscriptionOneYear:
            "Subscription 1y"
        }
    }

    var shortTitle: String {
        switch self {
        case .iap:
            "IAP"
        case .subscriptionOneWeek:
            "1 week"
        case .subscriptionOneMonth:
            "1 month"
        case .subscriptionOneYear:
            "1 year"
        }
    }

    var subtitle: String {
        switch self {
        case .iap:
            "In-App Purchase"
        case .subscriptionOneWeek, .subscriptionOneMonth, .subscriptionOneYear:
            "Subscription"
        }
    }

    var selectorTitle: String {
        switch self {
        case .iap:
            "IAP"
        case .subscriptionOneWeek:
            "1w"
        case .subscriptionOneMonth:
            "1m"
        case .subscriptionOneYear:
            "1y"
        }
    }

    var detailTitle: String {
        switch self {
        case .iap:
            "In-App Purchase"
        case .subscriptionOneWeek:
            "Subscription, 1 week"
        case .subscriptionOneMonth:
            "Subscription, 1 month"
        case .subscriptionOneYear:
            "Subscription, 1 year"
        }
    }

    init?(productType: String) {
        let normalized = productType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("week") || normalized == "1w" || normalized.contains("1 w") {
            self = .subscriptionOneWeek
        } else if normalized.contains("month") || normalized == "1m" || normalized.contains("1 m") {
            self = .subscriptionOneMonth
        } else if normalized.contains("year") || normalized == "1y" || normalized.contains("1 y") {
            self = .subscriptionOneYear
        } else if normalized.contains("subscription") {
            self = .subscriptionOneMonth
        } else if normalized.contains("iap") || normalized.contains("non-consumable") || normalized.contains("consumable") {
            self = .iap
        } else {
            return nil
        }
    }
}

private struct OfferKindSelection: View {
    @Binding var selection: OfferKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Type")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(selection.detailTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Type", selection: $selection) {
                ForEach(OfferKind.allCases) { kind in
                    Text(kind.selectorTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct ExpirationPicker: View {
    @Binding var hasExpiry: Bool
    @Binding var expiresAt: Date

    var body: some View {
        Group {
            Toggle(isOn: expiryToggleBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expires")

                    Text(hasExpiry ? Self.dateFormatter.string(from: expiresAt) : "None")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if hasExpiry {
                DatePicker(
                    "Expiration Date",
                    selection: $expiresAt,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }
        }
    }

    private var expiryToggleBinding: Binding<Bool> {
        Binding {
            hasExpiry
        } set: { newValue in
            if newValue, !hasExpiry {
                withAnimation {
                    expiresAt = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                    hasExpiry = true
                }
            } else {
                withAnimation {
                    hasExpiry = newValue
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct AppStoreSearchField: View {
    @Binding var query: String
    let isSearching: Bool
    let search: () -> Void

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search App Store", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if canSearch {
                        search()
                    }
                }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Search", action: search)
                    .font(.subheadline.weight(.semibold))
                    .disabled(!canSearch)
            }
        }
    }
}
private struct AppStoreSearchResultsList: View {
    let results: [AppStoreAppInfo]
    let selectedApp: AppStoreAppInfo?
    let select: (AppStoreAppInfo) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { result in
                    Button {
                        select(result)
                    } label: {
                        AppStoreInfoPreview(info: result, showsSelection: selectedApp == result)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    if result.id != results.last?.id {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }
}

private struct AppStoreInfoPreview: View {
    let info: AppStoreAppInfo
    var showsSelection = false

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

            if showsSelection {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct ProductDetailView: View {
    let product: OfferProduct
    let share: (CodeEntry) -> Void
    let copy: (CodeEntry) -> Void
    let shareQRCode: (CodeEntry) -> Void
    let export: () -> Void
    let updateProduct: (OfferProduct, String?, String, Date?) -> Void
    let deleteProduct: (OfferProduct) -> Void
    let markUsed: (OfferProduct, Int) -> Void
    @State private var sheet: ProductDetailSheet?
    @State private var isConfirmingDelete = false

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
                            OfferCodeActions(
                                code: nextCode,
                                copy: { copy(nextCode) },
                                share: { share(nextCode) },
                                shareQRCode: { shareQRCode(nextCode) }
                            )
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

                    Button(action: export) {
                        Label("Export CSV", systemImage: "doc.badge.arrow.up")
                    }

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Offer", systemImage: "trash")
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
                ProductEditSheet(product: product) { customName, productType, expiresAt in
                    updateProduct(product, customName, productType, expiresAt)
                }
            case .markUsed:
                BulkMarkUsedSheet(product: product) { count in
                    markUsed(product, count)
                }
            }
        }
        .confirmationDialog("Delete \(product.displayProductName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Offer", role: .destructive) {
                deleteProduct(product)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the offer and all codes saved for it.")
        }
    }

    private static let expiryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct OfferCodeActions: View {
    let code: CodeEntry
    let copy: () -> Void
    let share: () -> Void
    let shareQRCode: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 10) {
            Button(action: copy) {
                HStack(spacing: 10) {
                    Text(code.code)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer()

                    Image(systemName: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy code \(code.code)")

            LazyVGrid(columns: columns, spacing: 10) {
                OfferActionButton(title: "Share Link", systemImage: "square.and.arrow.up", action: share, isProminent: true)
                OfferActionButton(title: "Share QR Code", systemImage: "qrcode", action: shareQRCode)
            }
        }
    }
}

private struct OfferActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var isProminent = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .liquidGlassButtonStyle(prominent: isProminent)
    }
}

private enum ProductDetailSheet: String, Identifiable {
    case edit
    case markUsed

    var id: String { rawValue }
}

private struct ProductEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let product: OfferProduct
    let save: (String?, String, Date?) -> Void
    @State private var name: String
    @State private var offerKind: OfferKind
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date

    init(product: OfferProduct, save: @escaping (String?, String, Date?) -> Void) {
        self.product = product
        self.save = save
        _name = State(initialValue: product.displayProductName)
        _offerKind = State(initialValue: OfferKind(productType: product.productType) ?? .iap)
        _hasExpiry = State(initialValue: product.expiresAt != nil)
        _expiresAt = State(initialValue: product.expiresAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Offer") {
                    TextField("Name", text: $name)

                    OfferKindSelection(selection: $offerKind)

                    ExpirationPicker(hasExpiry: $hasExpiry, expiresAt: $expiresAt)
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
                        save(trimmedName == product.productName ? nil : trimmedName, offerKind.title, hasExpiry ? expiresAt : nil)
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
