//  AvatarEditorView.swift
import SwiftUI
import SceneKit
import UIKit

struct AvatarEditorView: View {
    @ObservedObject var userModel: UserModel
    @Environment(\.presentationMode) private var dismiss

    // MARK: – State
    @State private var wheelIndex: Int = 0            // show overlay immediately
    @State private var avatarGender: String = "male"
    private let labels = ["Height", "Chest", "Waist", "Hip", "Sleeve", "Inseam"]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // ← White background filling the entire tab
                Color.white
                    .ignoresSafeArea()

                // 3D preview: shrink and shift right when wheel is present
                SceneKitContainer(
                    avatarURL: userModel.avatarURL,
                    environment: userModel.environment,
                    measurements: userModel.measurements,
                    avatarGender: $avatarGender
                )
                .ignoresSafeArea()
                .scaleEffect(wheelIndex >= 0 ? 0.6 : 1.0)
                .offset(x: wheelIndex >= 0 ? geo.size.width * 0.25 : 0)
                .animation(.easeOut(duration: 0.3), value: wheelIndex)

                // Close button
                Button {
                    dismiss.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.black) // visible on white
                        .padding(.top, 52)
                        .padding(.leading, 20)
                }

                // Wheel overlay moved further left and down
                WheelOverlay(
                    measurements: userModel.measurements,
                    labels: labels
                )
                .scaleEffect(0.8)                             // 80% size
                .offset(
                    x: -40,                                    // moved 40px left of screen edge
                    y: geo.size.height * 0.2                  // moved further down
                )
                .onAppear { wheelIndex = 0 }  // ensure visible
            }
            .statusBar(hidden: true)
        }
    }
}

// MARK: – WheelOverlay View
private struct WheelOverlay: View {
    @ObservedObject var measurements: AvatarMeasurements
    let labels: [String]

    private let wheelHeight: CGFloat = 300
    private let rowHeight: CGFloat = 100
    private let rowSpacing: CGFloat = 20

    var body: some View {
        ZStack {
            Color.clear

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: rowSpacing) {
                    // Loop: each measurement + one Reset
                    ForEach(0 ..< labels.count + 1, id: \.self) { i in
                        if i < labels.count {
                            RowView(
                                index: i,
                                label: labels[i],
                                measurement: binding(for: i),
                                wheelHeight: wheelHeight,
                                rowHeight: rowHeight
                            )
                            .frame(height: rowHeight)
                        } else {
                            ResetRowView(
                                wheelHeight: wheelHeight,
                                rowHeight: rowHeight
                            ) {
                                measurements.reset()
                            }
                            .frame(height: rowHeight)
                        }
                    }
                }
                .padding(.vertical, (wheelHeight - rowHeight) / 2)
                .padding(.horizontal, 16)
            }
            .coordinateSpace(name: "wheelSpace")
            .frame(height: wheelHeight)
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .frame(height: wheelHeight)
    }

    private func binding(for idx: Int) -> Binding<Float> {
        switch idx {
        case 0: return $measurements.height
        case 1: return $measurements.chest
        case 2: return $measurements.waist
        case 3: return $measurements.hip
        case 4: return $measurements.sleeveLength
        case 5: return $measurements.inseam
        default: fatalError("Invalid index")
        }
    }
}

// MARK: – RowView (per-row logic)
private struct RowView: View {
    let index: Int
    let label: String
    @Binding var measurement: Float
    let wheelHeight: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        GeometryReader { itemGeo in
            let midY = itemGeo.frame(in: .named("wheelSpace")).midY
            let center = wheelHeight / 2
            let dist = abs(midY - center)
            let normalized = max(0, 1 - (dist / center))

            // Larger fonts
            let minFont: CGFloat = 16
            let maxFont: CGFloat = 24
            let fontSize = minFont + (maxFont - minFont) * normalized

            // Scale for slider height
            let minScale: CGFloat = 0.6
            let maxScale: CGFloat = 1.0
            let scale = minScale + (maxScale - minScale) * normalized

            // Track colors: light purple track, purple thumb
            let trackColor = Color.purple.opacity(0.3)
            let thumbColor = Color.purple

            VStack(alignment: .leading, spacing: 12) {
                Text(label)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(.purple)

                ZStack {
                    // Light purple track, thicker and full width
                    Capsule()
                        .fill(trackColor)
                        .frame(width: (rowHeight * 4) * scale, height: 16 * scale)

                    // Slider with invisible track, purple circular thumb
                    Slider(
                        value: $measurement,
                        in: range(for: index),
                        step: 0.5
                    )
                    .tint(thumbColor)
                    .scaleEffect(x: scale, y: scale, anchor: .center) // circular thumb
                    .frame(width: (rowHeight * 4) * scale)
                    .background(Color.clear)
                }
                .frame(height: 16 * scale)

                // Combined cm and in text
                Text(String(
                    format: "%.1f cm %.1f in",
                    measurement,
                    measurement / 2.54
                ))
                .font(.system(size: fontSize * 0.8))
                .foregroundColor(.purple)
            }
            .padding()
            .scaleEffect(scale)
        }
    }

    private func range(for idx: Int) -> ClosedRange<Float> {
        switch idx {
        case 0: return 140...210
        case 1: return 80...130
        case 2: return 60...120
        case 3: return 80...130
        case 4: return 40...80
        case 5: return 60...100
        default: fatalError("Invalid index")
        }
    }
}

// MARK: – ResetRowView
private struct ResetRowView: View {
    let wheelHeight: CGFloat
    let rowHeight: CGFloat
    let action: () -> Void

    var body: some View {
        GeometryReader { itemGeo in
            let midY = itemGeo.frame(in: .named("wheelSpace")).midY
            let center = wheelHeight / 2
            let dist = abs(midY - center)
            let normalized = max(0, 1 - (dist / center))

            // Larger font for Reset
            let minFont: CGFloat = 16
            let maxFont: CGFloat = 24
            let fontSize = minFont + (maxFont - minFont) * normalized

            // Scale
            let minScale: CGFloat = 0.6
            let maxScale: CGFloat = 1.0
            let scale = minScale + (maxScale - minScale) * normalized

            HStack {
                Spacer()
                Button(action: action) {
                    Text("Reset")
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.purple)
                        .cornerRadius(8)
                }
                .scaleEffect(scale)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: – UIColor Extensions
private extension UIColor {
    // Return a darker version by percentage
    func darker(by percent: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            return UIColor(
                red: max(r - percent/100, 0),
                green: max(g - percent/100, 0),
                blue: max(b - percent/100, 0),
                alpha: a
            )
        }
        return self
    }

    // Return inverse color (RGB flipped)
    func inverse() -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            return UIColor(red: 1 - r, green: 1 - g, blue: 1 - b, alpha: a)
        }
        return self
    }
}
