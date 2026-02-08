import SwiftUI
import WebKit

struct GenderSelectionView: View {
    @ObservedObject var userModel: UserModel
    
    // UI state
    @State private var name: String = ""
    @State private var selectedAvatarURL: String = ""
    @State private var showAvatarCreator = false
    @State private var showMainMenu   = false
    
    // MARK: – Body
    var body: some View {
        ZStack {
            /* ---------- lively background ---------- */
            LinearGradient(
                colors: [Color(#colorLiteral(red:0.09, green:0.32, blue:0.55, alpha:1)),
                         Color(#colorLiteral(red:0.27, green:0.47, blue:0.91, alpha:1)),
                         Color(#colorLiteral(red:0.57, green:0.33, blue:0.88, alpha:1))],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            /* ---------- floating glass card ---------- */
            VStack(spacing: 24) {
                // Brand hero
                Image("FitCheckLogo")            // put FitCheckLogo.png in Assets.xcassets
                    .resizable()
                    .scaledToFit()
                    .frame(height: 150)
                    .shadow(radius: 8)
                
                Text("Create Your Avatar")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                
                /* -- Glass-style form -- */
                VStack(spacing: 20) {
                    /* name field */
                    TextField("Enter your name", text: $name)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.15)))
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                    
                    /* avatar picker button */
                    Button {
                        showAvatarCreator = true
                    } label: {
                        HStack {
                            Image(systemName: selectedAvatarURL.isEmpty ? "person.crop.circle.badge.plus"
                                                                         : "checkmark.circle.fill")
                                .font(.title3)
                            Text(selectedAvatarURL.isEmpty ? "Choose your avatar"
                                                           : "Avatar selected")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [Color(#colorLiteral(red:0.25, green:0.82, blue:0.61, alpha:1)),
                                                    Color(#colorLiteral(red:0.11, green:0.67, blue:0.52, alpha:1))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.25), radius: 6, y: 4)
                    }
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2))
                )
                
                /* continue button */
                Button {
                    userModel.name = name
                    userModel.avatarURL = selectedAvatarURL
                    userModel.saveProfile()
                    showMainMenu = true
                } label: {
                    Text("Get Started")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 360)
                        .padding(.vertical, 16)
                        .background(selectedAvatarURL.isEmpty || name.isEmpty
                                    ? Color.gray.opacity(0.35)
                                    : Color(#colorLiteral(red:0.96, green:0.58, blue:0.23, alpha:1)))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .disabled(selectedAvatarURL.isEmpty || name.isEmpty)
                
                Spacer(minLength: 40)
            }
            .padding(.top)
            .padding(.horizontal)
        }
        /* ---------- avatar picker sheet ---------- */
        .sheet(isPresented: $showAvatarCreator) {
            AvatarWebView { url in
                selectedAvatarURL = url
                showAvatarCreator = false
            }
        }
        /* ---------- proceed to main app ---------- */
        .fullScreenCover(isPresented: $showMainMenu) {
            ContentView(userModel: userModel)
        }
    }
}


#if DEBUG
struct GenderSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        GenderSelectionView(userModel: UserModel())
    }
}
#endif
