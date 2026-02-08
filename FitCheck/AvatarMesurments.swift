import Foundation
import Combine

final class AvatarMeasurements: ObservableObject, Codable {
    @Published var height:        Float = 170   // 140 … 210 cm
    @Published var chest:         Float = 95    // 80  … 130
    @Published var waist:         Float = 80    // 60  … 120
    @Published var hip:           Float = 95    // 80  … 130
    @Published var sleeveLength:  Float = 60    // 40  … 80
    @Published var inseam:        Float = 80    // 60  … 100
    
    enum CodingKeys: String, CodingKey {
        case height, chest, waist, hip, sleeveLength, inseam
    }
    
    func reset() {
        height = 170; chest = 95; waist = 80; hip = 95
        sleeveLength = 60; inseam = 80
    }
    
    // MARK: – Codable support so we can write the whole struct to UserDefaults
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        height        = try c.decode(Float.self, forKey: .height)
        chest         = try c.decode(Float.self, forKey: .chest)
        waist         = try c.decode(Float.self, forKey: .waist)
        hip           = try c.decode(Float.self, forKey: .hip)
        sleeveLength  = try c.decode(Float.self, forKey: .sleeveLength)
        inseam        = try c.decode(Float.self, forKey: .inseam)
    }
    init() {}                         
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(height,        forKey: .height)
        try c.encode(chest,         forKey: .chest)
        try c.encode(waist,         forKey: .waist)
        try c.encode(hip,           forKey: .hip)
        try c.encode(sleeveLength,  forKey: .sleeveLength)
        try c.encode(inseam,        forKey: .inseam)
    }
}
