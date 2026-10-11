import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let guides = try JSONDecoder().decode([String: MeasurementGuide].self, from: data)
precondition(Set(guides.keys) == Set(MeasurementGuide.languages))
for language in MeasurementGuide.languages {
    let guide = guides[language]!
    precondition(guide.steps.count == 7)
    precondition(guide.steps.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty && !$0.icon.isEmpty })
    precondition(!guide.saveFiles.isEmpty && !guide.cloudHelp.isEmpty)
    let workflow = guide.workflow!
    precondition(workflow.stages.count == 4)
    precondition(workflow.stages.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    precondition(!workflow.prepareBody.isEmpty && !workflow.measureHint.isEmpty && !workflow.tutorial.isEmpty)
}
precondition(MeasurementGuide.languageCode("fr-CA") == "fr")
precondition(MeasurementGuide.languageCode("zh_TW") == "zh-Hans")
precondition(MeasurementGuide.languageCode("it") == "it")
precondition(MeasurementGuide.languageCode("en-US") == "de")

let ready = MeasurementWorkflowState(phase: .ready, canReconstruct: false, hasProjects: false)
precondition(ready.availableActions == [.scan] && ready.primaryAction == .scan)
let captured = MeasurementWorkflowState(phase: .captured, canReconstruct: true, hasProjects: true)
precondition(captured.availableActions == [.scan, .assemble, .library] && captured.primaryAction == .assemble)
let mesh = MeasurementWorkflowState(phase: .mesh, canReconstruct: true, hasProjects: true)
precondition(mesh.availableActions == [.scan, .assemble, .measure, .share, .library] && mesh.primaryAction == .measure)
let loadedMesh = MeasurementWorkflowState(phase: .mesh, canReconstruct: false, hasProjects: false)
precondition(!loadedMesh.availableActions.contains(.assemble) && loadedMesh.availableActions.contains(.measure))
let cloud = MeasurementWorkflowState(phase: .pointCloud, canReconstruct: false, hasProjects: false)
precondition(!cloud.availableActions.contains(.measure) && cloud.availableActions.contains(.share) && cloud.primaryAction == .share)
let active = MeasurementWorkflowState(phase: .busy, canReconstruct: true, hasProjects: true)
precondition(active.availableActions.isEmpty && active.primaryAction == nil)
print("Measurement guide: five languages, language fallback, and six scanner workflow states passed")
