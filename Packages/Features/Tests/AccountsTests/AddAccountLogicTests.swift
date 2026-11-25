import Foundation
import Testing

@testable import Accounts

/// Add an AI account (approved mockup 2026-11-25): which cards show, the key's hint, where a sign-in stands.
struct AddAccountLogicTests {
    func p(
        _ id: String, harness: String = "claude", login: [String] = ["paste"], prefix: String? = nil,
        hint: String? = nil, url: String? = nil, hidden: Bool = false
    ) -> ProviderItem {
        var x = ProviderItem(
            id: id, name: id.capitalized, harness: harness, authVar: "K", baseURL: "", delivery: [],
            loginMethods: login, models: [], pricedAt: nil, builtin: true, keyPrefix: prefix)
        (x.keyHint, x.keyURL, x.hidden) = (hint, url, hidden)
        return x
    }

    @Test func openCodeIsNeverACardOnAnyCore() {
        let list = [
            p("opencode-sub", harness: "opencode", login: ["runner_login"]),
            p("claude-sub", login: ["browser_code"]), p("codex-sub", harness: "codex", login: ["device_code"]),
            p("agy-sub", harness: "agy", login: ["runner_login"]),
            // A Core-added preset runs on OpenCode but is an API key: it stays.
            p("together", harness: "opencode"), p("openrouter"), p("anthropic"),
        ]
        #expect(AddCards.cards(list, .subscription).map(\.id) == ["claude-sub", "codex-sub", "agy-sub"])
        #expect(AddCards.cards(list, .apiKey).map(\.id) == ["openrouter", "anthropic", "together"])
        // A newer Core flags it hidden: whatever its id or harness.
        var flagged = p("someday-sub", harness: "claude", login: ["browser_code"])
        flagged.hidden = true
        #expect(AddCards.cards([flagged], .subscription).isEmpty)
    }

    @Test func cardFacesAndLogosFollowTheMockup() {
        #expect(AddCards.name(p("codex-sub")) == "ChatGPT" && AddCards.who(p("codex-sub")) == "OpenAI")
        #expect(AddCards.name(p("agy-sub")) == "Google" && AddCards.who(p("agy-sub")) == "Google")
        #expect(AddCards.logo("xai") == "ai-x" && AddCards.logo("groq") == "ai-groq")
        #expect(AddCards.logo("together") == "together", "no mark: the id, so the tile shows its letter")
        #expect(ConnLook.logos.contains(AddCards.logo("openrouter")))
    }

    @Test func theKeyPageComesFromTheCoreFirst() {
        #expect(AddCards.keyPage(p("openrouter"))?.absoluteString == "https://openrouter.ai/keys")
        #expect(
            AddCards.keyPage(p("openrouter", url: "https://example.com/k"))?.absoluteString == "https://example.com/k")
        #expect(AddCards.keyPage(p("together")) == nil)
        #expect(AddCards.keyPage(p("together", url: "http://plain.example")) == nil, "https only")
    }

    @Test func onlyADefinitionsPrefixBlocksAdd() {
        #expect(AddCards.keyStart(p("x", prefix: "abc-", hint: "zzz")) == ("abc-", true))
        #expect(AddCards.keyStart(p("openrouter", hint: "sk-or-v1-")) == ("sk-or-v1-", false))
        #expect(AddCards.keyStart(p("groq")) == ("gsk_", false))
        #expect(AddCards.keyStart(p("together")) == (nil, false))
    }

    @Test func theKeyHintReadsAsYouType() {
        #expect(KeyHint.of("", prefix: "sk-or-", name: "OpenRouter").words == "Starts with sk-or-")
        #expect(KeyHint.of("", prefix: nil, name: "Mistral").words == "Paste the whole key")
        #expect(KeyHint.of("sk-or-v1-0123456789", prefix: "sk-or-", name: "OpenRouter") == .looksRight)
        #expect(
            KeyHint.of("sk-ant-0123456789", prefix: "sk-or-", name: "OpenRouter").words
                == "OpenRouter keys start with sk-or-")
        #expect(KeyHint.of("0123456789abc", prefix: nil, name: "Mistral") == .looksRight)
    }

    @Test func theCoresStageWins() {
        var f = SignInFlow(stage: .open(URL(string: "https://example.invalid")!), label: "x")
        f.coreStage = "enter_code"
        #expect(SignInStep.of(f, style: .deviceCode) == .enterCode)
        f.coreStage = "finishing"
        #expect(SignInStep.of(f, style: .paste) == .finishing)
        f.coreStage = "something_new"
        #expect(SignInStep.of(f, style: .deviceCode) == .openURL, "an unknown word falls back to inference")
        f.stage = .done(account: 1)
        #expect(SignInStep.of(f, style: .paste) == .done)
        f.stage = .failed("no")
        #expect(SignInStep.of(f, style: .paste) == .failed)
    }

    @Test func anOlderCoresStageIsInferred() {
        #expect(SignInStep.of(nil, style: .paste) == .starting)
        var f = SignInFlow(stage: .starting, label: "x")
        #expect(SignInStep.of(f, style: .paste) == .starting)
        f.stage = .open(URL(string: "https://example.invalid")!)
        #expect(SignInStep.of(f, style: .paste) == .enterCode, "Claude's CLI asks for the code at once")
        #expect(SignInStep.of(f, style: .deviceCode) == .openURL)
        f.stage = .guided(URL(string: "https://example.invalid"))
        f.screen = ["Open this page to sign in:", "https://example.invalid", ""]
        #expect(SignInStep.of(f, style: .guided) == .openURL)
        f.screen += ["Paste the authorization code here:", ""]
        #expect(SignInStep.of(f, style: .guided) == .enterCode)
        f.sending = true
        #expect(SignInStep.of(f, style: .guided) == .finishing)
        f.sending = false
        f.stage = .working
        #expect(SignInStep.of(f, style: .paste) == .finishing)
        #expect(SignInStep.page(f) == nil)
        f.stage = .guided(URL(string: "https://example.invalid/a"))
        #expect(SignInStep.page(f)?.path == "/a")
    }

    /// Antigravity on an older Core (no auto-answer): its CLI waits on the login-method menu and prints no URL.
    @Test func antigravitysMenuBecomesChoices() {
        let agy = [
            "Select login method:", "> 1. Google OAuth", "  2. Use a Google Cloud project", "",
            "↑/↓ Navigate · enter Select",
        ]
        let want = [
            MenuOption(number: "1", title: "Google OAuth"),
            MenuOption(number: "2", title: "Use a Google Cloud project"),
        ]
        #expect(GuidedMenu.options(agy) == want)
        // The same screen squashed onto one line.
        #expect(
            GuidedMenu.options(
                ["Select login method: > 1. Google OAuth  2. Use a Google Cloud project  ↑/↓ Navigate · enter Select"])
                == want)
        #expect(GuidedMenu.options(["Opening https://example.invalid/v2.1. now", "Paste the code:"]).isEmpty)
        #expect(GuidedMenu.options(["1. Only one"]).isEmpty)
        var f = SignInFlow(stage: .guided(nil), label: "x")
        f.screen = agy
        #expect(SignInStep.of(f, style: .guided) == .chooseMethod)
        #expect(GuidedInput.check("1", provider: "agy-sub") == .send("1"), "the Core takes the choice's number")
        f.stage = .guided(URL(string: "https://example.invalid"))
        #expect(SignInStep.of(f, style: .guided) == .chooseMethod, "back on its menu after an error: asked again")
        f.screen = agy + ["Please visit https://accounts.google.com/o/oauth2/auth?x=1", "Waiting…"]
        #expect(SignInStep.of(f, style: .guided) == .openURL, "a page once it prints one")
    }

    static let agyMenu = [
        "Select login method:", "> 1. Google OAuth", "  2. Use a Google Cloud project", "",
        "↑/↓ Navigate · enter Select",
    ]

    /// The owner's run: Google OAuth picked, the CLI opened the browser itself (no page reached the Core) and asks for
    /// the code under the old menu.
    @Test func aCodePromptUnderTheMenuAsksForTheCode() {
        var f = SignInFlow(stage: .guided(nil), label: "x")
        f.screen =
            Self.agyMenu + [
                "Please visit the following URL to authorize the application:",
                "https://accounts.example.invalid/o/oauth2",
                "", "Enter the authorization code:",
            ]
        #expect(SignInStep.of(f, style: .guided) == .enterCode)
    }

    @Test func aMenuWithOtherTextAfterItIsGone() {
        let screen = Self.agyMenu + ["Waiting for the browser sign-in…"]
        #expect(GuidedMenu.options(screen).isEmpty)
        var f = SignInFlow(stage: .guided(nil), label: "x")
        f.screen = screen
        #expect(SignInStep.of(f, style: .guided) == .openURL)
    }

    @Test func aMenuAtTheTailIsCurrentUntilAnsweredHere() {
        var f = SignInFlow(stage: .guided(nil), label: "x")
        f.screen = Self.agyMenu + [""]
        #expect(SignInStep.of(f, style: .guided) == .chooseMethod)
        f.pickedScreen = f.screen
        #expect(SignInStep.of(f, style: .guided) == .openURL, "picked: not asked again, the code field waits")
        f.screen = ["Pick a project:", "> 1. alpha", "  2. beta", "↑/↓ Navigate"]
        #expect(SignInStep.of(f, style: .guided) == .chooseMethod, "a new menu is asked")
    }

    @Test func theNewestGooglePageWinsAndTheErrorReadsPlainly() {
        let screen = [
            "Open https://accounts.google.com/o/oauth2/auth?code_challenge=OLD",
            "Got an error: token exchange failed: oauth2: \"invalid_grant\" \"Bad Request\"",
            "Open https://accounts.google.com/o/oauth2/auth?code_challenge=NEW",
            "Visit https://evil.example/x",
        ]
        #expect(SignInScreen.newestPage(screen)?.absoluteString.hasSuffix("NEW") == true)
        #expect(SignInScreen.lastError(screen)?.hasPrefix("Google didn’t accept") == true)
        #expect(SignInScreen.lastError(["Welcome"]) == nil)
    }
}
