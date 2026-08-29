//
//  AgentWorkerSetupPromptTests.swift
//  MacOS IconsTests
//

import Testing
@testable import MacOS_Icons

struct AgentWorkerSetupPromptTests {
    @Test
    func givesAgentTheCompleteWorkerSetupContract() {
        let prompt = AgentWorkerSetupPrompt.text

        #expect(prompt.contains("https://github.com/themattvision/macos-icons"))
        #expect(prompt.contains("MACOSICONS_API_KEY"))
        #expect(prompt.contains("CLIENT_AUTH_TOKEN"))
        #expect(prompt.contains("GET /health"))
        #expect(prompt.contains("WORKER_URL:"))
        #expect(prompt.contains("Non modificare il codice dell’app macOS."))
    }
}
