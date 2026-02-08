import SwiftUI

@main
struct FitCheckApp: App {
    @StateObject private var userModel = UserModel()

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(userModel)
                .onAppear { userModel.load() }
        }
    }
}
