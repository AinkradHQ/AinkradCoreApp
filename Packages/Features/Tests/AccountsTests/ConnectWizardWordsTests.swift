import Testing

@testable import Accounts

struct ConnectWizardWordsTests {
    @Test func theDialogNamesTheStep() {
        #expect(ConnectWizardWords.title(.provider, provider: "OpenAI", plan: false) == "Connect an account")
        #expect(ConnectWizardWords.title(.key, provider: "OpenAI", plan: false) == "Add your OpenAI key")
        #expect(ConnectWizardWords.title(.key, provider: "Claude", plan: true) == "Sign in to Claude")
        #expect(ConnectWizardWords.title(.name, provider: "OpenAI", plan: false) == "Name it and set a limit")
        #expect(ConnectWizardWords.title(.place, provider: "OpenAI", plan: false) == "Where does it go?")
    }

    @Test func theInstallLineSaysWhereAndHowFar() {
        #expect(ConnectWizardWords.installing(on: "Oracle", percent: 64) == "Installing on Oracle · 64%")
    }

    @Test func aProviderNoRunnerCanServeIsDimmed() {
        #expect(ConnectWizardWords.offered(.ready(runner: "Oracle", runnerID: "r1"), installable: false))
        #expect(ConnectWizardWords.offered(.notInstalled, installable: true))
        #expect(!ConnectWizardWords.offered(.notInstalled, installable: false))
        #expect(
            ConnectWizardWords.offered(.needsRunner, installable: false), "no runner online is a fix, not a dead end")
    }
}
