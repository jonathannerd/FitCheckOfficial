import SwiftUI

struct ClosetView: View {
    @EnvironmentObject private var userModel: UserModel
    @Environment(\.dismiss) private var dismiss

    // subtle gradient – tweak the colours if you like
    private let bgGradient = LinearGradient(
        colors: [Color.teal.opacity(0.35), Color.indigo.opacity(0.45)],
        startPoint: .topLeading,
        endPoint:   .bottomTrailing
    )

    var body: some View {
        NavigationView {
            ZStack {
                bgGradient.ignoresSafeArea()

                // List gives you swipe‑to‑delete “for free”
                List {
                    ForEach(userModel.closetItems, id: \.id) { item in
                        ClosetRow(item: item) {
                            remove(item)          // <- trash‑button action
                        }
                        .listRowBackground(Color.clear)   // transparent rows over gradient
                    }
                    .onDelete { indexSet in               // <- swipe‑to‑delete
                        userModel.closetItems.remove(atOffsets: indexSet)
                    }
                }
                .scrollContentBackground(.hidden)          // remove default blur
            }
            .navigationTitle("Your Closet")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()                           // toggles swipe‑delete UI
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func remove(_ item: ClothingItem) {
        userModel.closetItems.removeAll { $0.id == item.id }
    }
}

// MARK: – Row
private struct ClosetRow: View {
    let item: ClothingItem
    var onDelete: () -> Void       // injected from the parent

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: item.imageUrl)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                case .failure(_):
                    Color.gray
                default:
                    ProgressView()
                }
            }
            .frame(width: 70, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack {
                    Button("Buy") {
                        if let url = URL(string: "https://www.amazon.ca/dp/\(item.id)?tag=yonsher06-20") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Wear") { wear(item) }
                        .buttonStyle(.bordered)

                    Spacer()

                    // tiny trash icon
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // identical to the helper in ShoppingView
    private func wear(_ item: ClothingItem) {
        if let asset = item.assetURL, !asset.isEmpty {
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
