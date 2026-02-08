import SwiftUI
import SceneKit
import Foundation

struct ContentView: View {
    @ObservedObject var userModel: UserModel
    @State private var showSettingsSheet = false
    @State private var showCustomizationSheet = false
    @State private var currentAnimationIndex: Int = 0
    @State private var showShoppingView = false
    @State private var showClosetView = false
    @State private var avatarGender: String = "male"
    
    let animationFileNames = ["Running", "Walking", "Sitting", "Waving", "Idle"]

    var body: some View {
        ZStack {
            SceneKitContainer(avatarURL: userModel.avatarURL, environment: userModel.environment, measurements: userModel.measurements,avatarGender: $avatarGender)
                .edgesIgnoringSafeArea(.all)
            
            // Top overlay: Name and Settings button.
            VStack {
                HStack {
                    Text("Name: \(userModel.name)")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                    Spacer()
                    SidebarButton(title: "⚙️") {
                        showSettingsSheet = true
                    }
                    .padding(.top, 30)
                    .padding(.trailing, 10)
                }
                Spacer()
            }
            
            // Bottom-right sidebar: Four side buttons with emojis.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        SidebarButton(title: "👤") {
                            showCustomizationSheet = true
                        }
                        SidebarButton(title: "🛍️") {
                            showShoppingView = true
                        }
                        SidebarButton(title: "👕") {
                            showClosetView = true
                        }
                        SidebarButton(title: "🏃") {
                            currentAnimationIndex = (currentAnimationIndex + 1) % animationFileNames.count
                                            let baseName = animationFileNames[currentAnimationIndex]
                                            let suffix   = avatarGender == "female" ? "_female" : "_male"
                                            let gendered = baseName + suffix

                                            // try gendered first, fallback to base
                                            let url = Bundle.main.url(forResource: gendered, withExtension: "dae")
                                                   ?? Bundle.main.url(forResource: baseName,  withExtension: "dae")

                                            if let animationURL = url {
                                                print("Selected animation: \(animationURL.lastPathComponent)")
                                                NotificationCenter.default.post(name: .animationSelected,
                                                                                object: animationURL)
                                            } else {
                                                print("❌ Could not find \(gendered).dae or \(baseName).dae")
                                            }
                                        }
                    }
                    .padding(.bottom, 20)
                    .padding(.trailing, 10)
                }
            }
        }
        .sheet(isPresented: $showCustomizationSheet) {
            AvatarEditorView(userModel: userModel)
        }
        .fullScreenCover(isPresented: $showClosetView) {
             ClosetView()
            .environmentObject(userModel)
         }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet {
                userModel.clear()
                userModel.measurements.reset()
            }
            .environmentObject(userModel)
        }
         .fullScreenCover(isPresented: $showShoppingView) {
             ShoppingView()
               .environmentObject(userModel)
         }

    }
}


// MARK: - SettingsSheet
struct SettingsSheet: View {
    /// passed from ContentView
    var newModelAction: () -> Void
    
    /// for dismissal & shared data
    @Environment(\.dismiss)            private var dismiss
    @EnvironmentObject                 private var userModel: UserModel
    
    /// background options
    private let backgrounds: [String] = ["White", "Office", "School"]
    
    var body: some View {
        ZStack {
            /// blurred backdrop
            Color(.systemBackground)
                .opacity(0.97)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 28) {
                    // MARK: – Header
                    VStack(spacing: 8) {
                        Image("FitCheckLogo")          // add 200 × 200 png to Assets
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80)
                            .shadow(radius: 5)
                        
                        Text("Settings")
                            .font(.largeTitle.weight(.bold))
                        
                        Text("FitCheck is your **virtual fitting room**: create an avatar, try on outfits in 3-D, and order what actually fits.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                    }
                    
                    // MARK: – Environment picker
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preview Background")
                            .font(.headline)
                        Picker("", selection: $userModel.environment) {
                            ForEach(backgrounds, id: \.self) { option in
                                Text(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(radius: 6)
                    .padding(.horizontal)
                    
                    // MARK: – Actions
                    VStack(spacing: 12) {
                        Button {
                            NotificationCenter.default.post(name: .resetAvatar, object: nil)
                            newModelAction()
                            dismiss()
                        } label: {
                            Label("Create New Model", systemImage: "person.crop.circle.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal)
                        
                        Button("Done") { dismiss() }
                            .font(.headline)
                            .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 32)
            }
        }
    }
}
extension Notification.Name {
    static let resetAvatar = Notification.Name("ResetAvatar")
}
