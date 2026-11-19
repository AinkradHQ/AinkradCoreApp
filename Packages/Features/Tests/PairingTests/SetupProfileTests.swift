import Foundation
import Testing

@testable import Pairing

@MainActor
struct SetupProfileTests {
    @Test func nothingAnsweredSendsNothing() {
        #expect(SetupProfile().items.isEmpty)
    }

    @Test func theNameIsTheFirstAnswerAndIsTrimmed() {
        var p = SetupProfile()
        p.name = "  Sam  "
        p.roleSet = ["Design"]
        #expect(p.items.map(\.key) == ["name", "role"])
        #expect(p.items[0].body == "Prefers to be called Sam.")
    }

    @Test func eachPageBecomesOneSentenceInTheOrderOfItsChoices() {
        var p = SetupProfile()
        p.roleSet = ["Design", "Build software"]
        p.languageSet = ["Go", "Swift"]
        p.tone = 0
        let items = p.items
        #expect(items.map(\.key) == ["role", "languages", "tone"])
        #expect(items[0].body == "Does this kind of work: Build software, Design.")
        #expect(items[1].body == "Programs in: Swift, Go.")
    }

    @Test func theStandardWeekIsADefaultNotAnAnswer() {
        var p = SetupProfile()
        #expect(!p.items.contains { $0.key == "hours" })
        p.applyQuick(.init(from: 10, to: 18))
        let hours = p.items.first { $0.key == "hours" }
        #expect(hours?.body.hasPrefix("Works Mon-Fri 10-18, Sat-Sun off (") == true)
    }

    @Test func splitDaysAndDaysOffReadPlainly() {
        var p = SetupProfile()
        p.setRange("Wed", at: 0, to: .init(from: 9, to: 13))
        let added = p.addRange("Wed")
        #expect(added)
        #expect(p.hours["Wed"] == [.init(from: 9, to: 13), .init(from: 14, to: 18)])
        p.toggleDay("Sat")
        p.toggleDay("Sat")
        let text = SetupProfile.hoursText(p.hours)
        #expect(text == "Mon-Tue 9-17, Wed 9-13 and 14-18, Thu-Fri 9-17, Sat-Sun off")
    }

    @Test func aFullDayTakesNoMoreRanges() {
        var p = SetupProfile()
        p.hours["Mon"] = [.init(from: 8, to: 23)]
        let added = p.addRange("Mon")
        #expect(!added)
    }

    @Test func variableAndOnCallHoursSayWhatTheyMean() {
        var p = SetupProfile()
        p.hoursMode = .vary
        #expect(p.items.first { $0.key == "hours" }?.body.contains("change from day to day") == true)
        p.hoursMode = .onCall
        #expect(p.items.first { $0.key == "hours" }?.body.contains("quiet hours 0-6 and 22-24") == true)
        p.quiet = []
        #expect(p.items.first { $0.key == "hours" }?.body == "On call: any hour can be work time.")
    }

    @Test func everySentenceFitsWhatTheCoreKeeps() {
        var p = SetupProfile()
        p.toolSet = Set(SetupProfile.tools)
        p.goalSet = Set(SetupProfile.goals)
        #expect(p.items.allSatisfy { $0.body.count <= 200 && !$0.body.isEmpty })
    }
}

@MainActor
struct SetupTourTests {
    @Test func theTourRunsOnlyWhenArmedAndSavesTheProfileLeavingTheLastAboutYouPage() async {
        var sent: [[SetupProfile.Item]] = []
        let m = SetupTourModel(
            macRunner: nil,
            save: {
                sent.append($0)
                return true
            })
        m.startIfArmed()
        #expect(!m.isActive)
        m.arm()
        m.startIfArmed()
        #expect(m.step == .role)
        m.profile.roleSet = ["Design"]
        while m.step != .life { m.next() }
        m.next()
        for _ in 0..<200 where m.saved == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(sent.count == 1 && sent[0].first?.key == "role" && m.saved == true)
        #expect(m.aboutLine == "Saved to your Brain")
    }

    @Test func skippingEverythingSendsNothingAndSaysSo() {
        let m = SetupTourModel(
            macRunner: nil,
            save: { _ in
                Issue.record("nothing to send")
                return true
            })
        m.begin()
        while m.step != .ready { m.next() }
        #expect(m.aboutLine == "Skipped for now")
        m.finish()
        #expect(!m.isActive)
    }
}

@MainActor
struct SetupDetourTests {
    @Test func anAboutYouDetourEndsOnTheWelcomePageAndSendsNothing() {
        var sent = 0
        let m = SetupTourModel(
            macRunner: nil,
            save: { _ in
                sent += 1
                return true
            })
        m.beginDetour(.you)
        m.profile.roleSet = ["Design"]
        #expect(m.step == .role && !m.isFirst)
        while m.step != .life { m.next() }
        m.next()
        #expect(m.step == nil && m.detour == nil && sent == 0)
        #expect(m.profile.roleSet == ["Design"], "the answers wait for the tour")
    }

    @Test func backOnTheFirstDetourPageAndTheLookDetourReturnToWelcome() {
        let m = SetupTourModel(macRunner: nil, save: { _ in true })
        m.beginDetour(.you)
        m.back()
        #expect(m.step == nil)
        m.beginDetour(.look)
        #expect(m.step == .look)
        m.next()
        #expect(m.step == nil && m.detour == nil)
    }
}
