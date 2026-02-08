import SwiftUI

/// emitted when user taps “Wear”
extension Notification.Name {
    static let clothingSelected = Notification.Name("clothingSelected")
}

struct ShoppingView: View {
    @EnvironmentObject private var userModel: UserModel
    @StateObject private var searchVM = ClothingSearchViewModel()
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    // fire only once
    @State private var didBootstrap = false

    var body: some View {
        NavigationView {
            VStack {
                // ── search bar ───────────────────────────────────────────────
                HStack {
                    TextField("Search clothing…", text: $query, onCommit: {
                        searchVM.search(for: query)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                    Button("Go") { searchVM.search(for: query) }
                        .padding(.trailing)
                }

                // ── results ────────────────────────────────────────────────
                if searchVM.items.isEmpty {
                    // neat little placeholder while loading / no results
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for nice pieces…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchVM.items) { item in
                        VStack(alignment: .leading, spacing: 8) {

                            // title
                            Text(item.title)
                                .font(.headline)

                            // thumbnail
                            AsyncImage(url: URL(string: item.imageUrl)) { phase in
                                switch phase {
                                case .success(let img):
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: 180)
                                        .cornerRadius(8)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: 180)
                                default:
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: 180)
                                }
                            }

                            // buttons
                            HStack {
                                Button("Add to Closet") {
                                    if !userModel.closetItems.contains(where: { $0.id == item.id }) {
                                        userModel.closetItems.append(item)
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Wear") {
                                    wear(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Shop")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "chevron.left")
                    }
                }
            }
            // ── bootstrap with a default search so the list isn’t empty ──
            .onAppear {
                guard !didBootstrap else { return }
                didBootstrap = true
                searchVM.search(for: "autumn clothing")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: – helpers
    private func wear(_ item: ClothingItem) {
        if let asset = item.assetURL, !asset.isEmpty {
            // ready‑made 3‑D model path (old flow)
            NotificationCenter.default.post(name: .clothingSelected, object: item)
        } else if
            let fStr = item.frontURL, let bStr = item.backURL,
            let f = URL(string: fStr), let b = URL(string: bStr) {

            let pg = PendingGarment(
                asin:  item.id,
                kind:  item.kind,
                frontURL: f,
                backURL:  b
            )
            NotificationCenter.default.post(name: .pendingGarmentReady, object: pg)
        } else {
            print("❌ No imagery for \(item.title)")
        }
    }
}
