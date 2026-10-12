import Foundation

struct MeasurementGuide: Decodable {
    struct Step: Decodable { let title: String; let icon: String; let body: String }
    struct Workflow: Decodable {
        struct Stage: Decodable { let title: String; let detail: String }
        let stages: [Stage]
        let tutorial: String
        let projects: String
        let overview: String
        let availableLater: String
        let readyTitle: String
        let capturedTitle: String
        let modelTitle: String
        let prepareTitle: String
        let prepareBody: String
        let enableLidar: String
        let scanHint: String
        let measureHint: String
    }
    let name: String
    let title: String
    let subtitle: String
    let next: String
    let back: String
    let done: String
    let close: String
    let language: String
    let start: String
    let assemble: String
    let measure: String
    let share: String
    let saveFiles: String
    let shareOther: String
    let cloudTitle: String
    let cloudHelp: String
    let steps: [Step]
    let workflow: Workflow?
    let roomPlan: [String: String]?
    let objectCapture: [String: String]?
    let splat: [String: String]?
    let sceneCapture: [String: String]?

    static func roomText(_ key: String) -> String {
        all[selectedLanguage]?.roomPlan?[key] ?? all["de"]?.roomPlan?[key] ?? key
    }
    static func objectText(_ key: String) -> String {
        all[selectedLanguage]?.objectCapture?[key] ?? all["de"]?.objectCapture?[key] ?? key
    }
    static func splatText(_ key: String) -> String {
        all[selectedLanguage]?.splat?[key] ?? all["de"]?.splat?[key] ?? key
    }
    static func sceneText(_ key: String) -> String {
        all[selectedLanguage]?.sceneCapture?[key] ?? all["de"]?.sceneCapture?[key] ?? key
    }

    static let languages = ["de", "en", "fr", "es", "it", "zh-Hans", "pt", "ar", "hi", "bn", "ru", "ja", "ko", "id", "tr"]
    static var isRightToLeft: Bool { selectedLanguage == "ar" }
    static let all = load()
    static func languageCode(_ preferred: String) -> String {
        let code = preferred.lowercased().replacingOccurrences(of: "_", with: "-")
        if code.hasPrefix("zh") { return "zh-Hans" }
        if code == "in" || code.hasPrefix("in-") { return "id" }
        return languages.first(where: { code == $0 || code.hasPrefix($0 + "-") }) ?? "de"
    }
    static var selectedLanguage: String {
        get { languageCode(UserDefaults.standard.string(forKey: "MeasurementGuideLanguage") ?? Locale.preferredLanguages.first ?? "de") }
        set { UserDefaults.standard.set(languageCode(newValue), forKey: "MeasurementGuideLanguage") }
    }
    static func load(bundle: Bundle = .main) -> [String: MeasurementGuide] {
        guard let url = bundle.url(forResource: "MeasurementGuide", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let guides = try? JSONDecoder().decode([String: MeasurementGuide].self, from: data) else { return [:] }
        return guides
    }
}

enum MeasurementAction: Hashable { case scan, assemble, measure, share, library }

/// Availability describes actual scanner state, not completed onboarding steps.
struct MeasurementWorkflowState {
    enum Phase { case ready, captured, mesh, pointCloud, busy }
    let phase: Phase
    let canReconstruct: Bool
    let hasProjects: Bool

    var availableActions: Set<MeasurementAction> {
        guard phase != .busy else { return [] }
        var actions: Set<MeasurementAction> = [.scan]
        if canReconstruct { actions.insert(.assemble) }
        if phase == .mesh { actions.insert(.measure) }
        if phase == .mesh || phase == .pointCloud { actions.insert(.share) }
        if hasProjects { actions.insert(.library) }
        return actions
    }
    var primaryAction: MeasurementAction? {
        switch phase {
        case .ready: return .scan
        case .captured: return canReconstruct ? .assemble : .scan
        case .pointCloud: return canReconstruct ? .assemble : .share
        case .mesh: return .measure
        case .busy: return nil
        }
    }
}
