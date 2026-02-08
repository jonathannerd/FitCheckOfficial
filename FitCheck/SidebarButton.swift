import SwiftUI

struct SidebarButton: View {
    let title: String
    let action: () -> Void

    // No default value—action must be provided.
    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(width: 50, height: 40)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
