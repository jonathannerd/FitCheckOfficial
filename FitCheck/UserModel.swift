import SwiftUI
import Combine

@MainActor
final class UserModel: ObservableObject {
    @Published var name       = ""
    @Published var gender     = ""
    @Published var avatarURL  = ""
    @Published var measurements = AvatarMeasurements()
    @Published var environment: String = "White"

    // ← NEW
    @Published var closetItems: [ClothingItem] = []

    private var cancellables = Set<AnyCancellable>()
    private enum Keys {
        static let profile      = "FitCheckProfile"
        static let measurements = "FitCheckMeasurements"
        static let environment  = "FitCheckEnvironment"
        static let closet       = "FitCheckCloset"
    }

    
    init() {
        load()

        // auto‐save environment
        $environment
            .sink { UserDefaults.standard.set($0, forKey: Keys.environment) }
            .store(in: &cancellables)

        // auto‐save measurements
        measurements.objectWillChange
            .sink { [weak self] in self?.saveMeasurements() }
            .store(in: &cancellables)

        // ← AUTO‐SAVE CLOSET
        $closetItems
            .sink { items in
                if let data = try? JSONEncoder().encode(items) {
                    UserDefaults.standard.set(data, forKey: Keys.closet)
                }
            }
            .store(in: &cancellables)
    }

    var hasSavedModel: Bool { !name.isEmpty && !avatarURL.isEmpty }

    func saveProfile() {
        let prof = ["name": name, "gender": gender, "avatarURL": avatarURL]
        UserDefaults.standard.set(prof, forKey: Keys.profile)
    }

    private func saveMeasurements() {
        let m: [String:Float] = [
            "height": measurements.height,
            "chest": measurements.chest,
            "waist": measurements.waist,
            "hip": measurements.hip,
            "sleeveLength": measurements.sleeveLength,
            "inseam": measurements.inseam
        ]
        UserDefaults.standard.set(m, forKey: Keys.measurements)
    }

    func load() {
        let d = UserDefaults.standard
        environment = d.string(forKey: Keys.environment) ?? "White"
        if let prof = d.dictionary(forKey: Keys.profile) as? [String:String] {
            name      = prof["name"]      ?? ""
            gender    = prof["gender"]    ?? ""
            avatarURL = prof["avatarURL"] ?? ""
        }
        if let m = d.dictionary(forKey: Keys.measurements) as? [String:Float] {
            measurements.height       = m["height"]       ?? measurements.height
            measurements.chest        = m["chest"]        ?? measurements.chest
            measurements.waist        = m["waist"]        ?? measurements.waist
            measurements.hip          = m["hip"]          ?? measurements.hip
            measurements.sleeveLength = m["sleeveLength"] ?? measurements.sleeveLength
            measurements.inseam       = m["inseam"]       ?? measurements.inseam
        }
        // ← LOAD CLOSET
        if let data = d.data(forKey: Keys.closet),
           let items = try? JSONDecoder().decode([ClothingItem].self, from: data) {
            closetItems = items
        }
    }

    func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Keys.profile)
        d.removeObject(forKey: Keys.measurements)
        d.removeObject(forKey: Keys.environment)
        d.removeObject(forKey: Keys.closet)
        name = ""; gender = ""; avatarURL = ""
        measurements.reset()
        environment = "White"
        closetItems.removeAll()
        saveProfile()
        saveMeasurements()
    }
}
