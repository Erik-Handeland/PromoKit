# PromoKit

PromoKit is a free, open-source SwiftUI app for developers who want a cleaner way to manage App Store promo and offer-code campaigns.

It helps organize codes by app and offer, share the next available code through the standard iOS share sheet, generate branded QR share cards, track recipients, and export the full code list with usage state preserved.

## Features

- Import App Store Connect offer-code CSVs
- Fetch app name, bundle ID, App Store URL, and app artwork from an App Store URL or app ID
- Organize multiple apps and offers
- Switch between shelf and compact views
- Share, copy, or QR-share the next available code
- Track recipient names
- Mark codes used individually or in bulk
- Set offer expiry dates and group expired offers
- Export full CSVs with `is_shared`, `shared_at`, and `recipient_name`
- Persist state in iCloud Documents when available, with local fallback
- Light, dark, and system appearance modes

## Privacy

Real promo-code CSVs should never be committed.

PromoKit ships with an empty bundled catalog:

- `Sources/PromoKit/Resources/products.json`

Private local seed data belongs in `LocalCodes`:

- `LocalCodes/products.json`
- `LocalCodes/*.csv`

The `LocalCodes` JSON and CSV files are ignored by git. Debug builds copy them into the app bundle for local testing. Release builds do not copy them.

## Local Seed Data

For local testing, add a private `LocalCodes/products.json`:

```json
{
  "products": [
    {
      "id": "my-app-offer",
      "appName": "My App",
      "appIconName": "DefaultAppIcon",
      "productName": "Annual",
      "productID": "com.example.myapp.yearly",
      "productType": "1 year",
      "status": "Approved",
      "codesResourceName": "my_app_annual"
    }
  ]
}
```

Then place the matching private CSV at `LocalCodes/my_app_annual.csv`:

```csv
<code>,<redeem_url>
```

Run:

```sh
xcodegen generate
```

Then build the Debug configuration in Xcode.

## Saved State

Runtime state is saved as JSON named `code_inventory_state.json`.

PromoKit first tries iCloud Documents:

```text
iCloud container/Documents/PromoKit/code_inventory_state.json
```

If iCloud is unavailable, it falls back to local Application Support:

```text
Application Support/PromoKit/code_inventory_state.json
```

Codes are not removed from the saved state document. Each code stays in the product's `codes` array and carries usage metadata.

## Development

PromoKit uses XcodeGen.

```sh
xcodegen generate
open PromoKit.xcodeproj
```

Before shipping under your own developer account:

- Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`
- Enable iCloud Documents for that bundle ID in Apple Developer
- Confirm the iCloud container in `Sources/PromoKit/PromoKit.entitlements`
- Keep product `id` values stable after release

## License

PromoKit is available under the MIT License.
