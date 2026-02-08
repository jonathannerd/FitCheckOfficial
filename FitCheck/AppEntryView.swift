import SwiftUI

struct AppEntryView: View {
    @StateObject var userModel = UserModel()
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                SplashView()
            } else {
                if userModel.hasSavedModel {
                    ContentView(userModel: userModel)
                } else {
                    GenderSelectionView(userModel: userModel)
                }
            }
        }
        .environmentObject(userModel)
        .onAppear {
            _ = GarmentTextureApplier.shared
            _ = GarmentProcessor.shared        // 🔌 spin up Step B listener
            userModel.load()
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                withAnimation {
                    isLoading = false
                }
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                Text("Loading AR Experience")
                    .font(.headline)
                    .foregroundColor(.black)
            }
        }
    }
}
