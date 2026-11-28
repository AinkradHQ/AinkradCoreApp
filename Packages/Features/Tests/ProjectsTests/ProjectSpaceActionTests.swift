import Foundation
import Testing

@testable import Projects

private func project(
    repos: Int = 1, fetched: Bool = true, run: RunSummary.State? = nil, draft: RunDraft? = nil, checked: Bool = false,
    kind: ProjectKind = .web
) -> ProjectItem {
    var p = ProjectItem(
        id: 1, slug: "tidepool", name: "Tidepool", description: "", expose: true,
        repos: (0..<repos).map {
            RepoItem(
                id: Int64($0), name: "r\($0)", remoteURL: "https://github.com/o/r\($0)", branch: "main",
                primary: $0 == 0, fetchedAt: fetched ? Date() : nil, fetchError: nil)
        },
        updatedAt: Date().addingTimeInterval(-7200))
    p.run = run.map { RunSummary(state: $0, lastRun: "20 min ago") }
    p.draft = draft
    p.setupChecked = checked
    p.kind = kind
    return p
}

struct MainActionTests {
    @Test func theActionFollowsTheState() {
        #expect(project(repos: 0).mainAction().kind == .addRepos)
        #expect(project(fetched: false).mainAction().kind == .waiting)
        #expect(project(fetched: false).mainAction().busy)
        #expect(project(checked: true).mainAction().kind == .setUp)
        let secrets = RunDraft(source: "compose", services: ["web"], secrets: ["jwt"])
        #expect(project(draft: secrets).mainAction().kind == .setSecrets)
        let ready = RunDraft(source: "compose", services: ["web"], secrets: [])
        #expect(project(draft: ready).mainAction().title == "Start")
        #expect(project(run: .stopped).mainAction().kind == .start)
        #expect(project(run: .failed).mainAction().title == "Start Again")
        #expect(project(run: .starting).mainAction().kind == .starting)
        #expect(project(run: .running).mainAction().kind == .open)
    }

    @Test func aPressedStartShowsStartingAtOnce() {
        let a = project(run: .stopped).mainAction(starting: true)
        #expect(a.kind == .starting && a.busy && a.title == "Starting…")
    }

    @Test func eachKindSaysItsOwnWords() {
        #expect(project(run: .stopped, kind: .app).mainAction().title == "Build and Run")
        #expect(project(repos: 0, kind: .other).mainAction().title == "New Doc…")
        var archived = project(kind: .other)
        archived.archived = true
        #expect(archived.mainAction().kind == .unarchive)
    }
}

struct SpaceBadgeTests {
    private let now = Date()

    @Test func aRunningWebProjectSaysRunningNotItsLink() {
        #expect(project(run: .running).spaceBadge(now: now).label == "Running")
    }

    @Test func neverRunProjectsAreReadyOrNeedSetupNotStopped() {
        let ready = RunDraft(source: "compose", services: ["web"], secrets: [])
        #expect(project(draft: ready).spaceBadge(now: now).label == "Ready to start")
        #expect(project(checked: true).spaceBadge(now: now).label == "Needs setup")
        #expect(project(repos: 0).spaceBadge(now: now).label == "No repos yet")
        #expect(project(fetched: false).spaceBadge(now: now).label == "Setting up")
        #expect(project().spaceBadge(now: now).label == "Setting up")  // copied, setup not read yet
        let secrets = RunDraft(source: "compose", services: ["web"], secrets: ["jwt"])
        #expect(project(draft: secrets).spaceBadge(now: now).label == "Needs secrets")
    }

    @Test func aStaleRunningProjectIsUnknownAndNotSoftwareSaysWhenItWasEdited() {
        var p = project(run: .running)
        p.stale = true
        #expect(p.spaceBadge(now: now).label == "Status unknown")
        #expect(p.controlBlock(canControl: true) != nil)
        #expect(project(repos: 0, kind: .other).spaceBadge(now: now).label.hasPrefix("Edited"))
    }
}

struct LastRunLogTests {
    @Test func theCaptionNamesTheLastRunOnceItEnded() {
        #expect(LogWords.caption(project(run: .running)) == "all services")
        #expect(LogWords.caption(project(run: .failed)) == "Last run · failed 20 min ago")
        #expect(LogWords.caption(project(run: .stopped)) == "Last run · stopped 20 min ago")
        #expect(LogWords.caption(project()) == nil)
    }

    @Test func errorLinesAreMarked() {
        #expect(LogWords.isError("web: npm ci exited with code 1"))
        #expect(!LogWords.isError("ready for connections"))
    }
}

struct FailureFixTests {
    @Test func aSecretFixNeedsTheFailureToNameTheSecret() {
        var p = project(run: .failed, draft: RunDraft(source: "compose", services: ["web"], secrets: ["stripe_secret"]))
        p.live = ProjectLive(failure: "api stopped", failureFix: "STRIPE_SECRET is not set.")
        #expect(p.failedSecret == "stripe_secret")
        p.live = ProjectLive(steps: [StartStep(title: "Building the app", state: .failed, detail: "no such module")])
        #expect(p.failedSecret == nil)
    }

    @Test func theStageAndTheHeaderUseTheSameWordPerKind() {
        #expect(project(run: .failed, kind: .app).mainAction().title == "Build Again")
        #expect(project(run: .failed, kind: .infra).mainAction().title == "Start Again")
        #expect(project(run: .failed, kind: .web).mainAction().title == "Start Again")
    }
}
