// CHANGE: Avoid type name collision with Integration/TemplateConfiguration

import Foundation

@MainActor
enum StudioModeTemplateDefaults {
    static func applyTemplateDefaults(to manager: PreviewProgramManager, for template: ProjectTemplate) async throws {
        manager.setStudioModeEnabled(template.studioModeDefault)
    }
}