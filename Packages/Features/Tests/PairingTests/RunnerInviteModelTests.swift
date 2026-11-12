import Foundation
import Testing

@testable import CoreKit
@testable import Pairing

@MainActor private final class Box {
    var status = "live"
    var names: [String] = ["old"]
    var withdrawn: [String] = []
    var made = 0
    var failWithdraw: (any Error)?
}

@MainActor private final class Board: LinkPasteboard {
    var changeCount = 0
    var text: String?
    func write(secret text: String) -> Int {
        self.text = text
        changeCount += 1
        return changeCount
    }
    func clear() {
        text = nil
        changeCount += 1
    }
}

@MainActor @Suite struct RunnerInviteModelTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(_ box: Box, board: Board = Board()) -> RunnerInviteModel {
        let t0 = t0
        return RunnerInviteModel(
            deps: RunnerInviteDeps(
                create: { name in
                    box.made += 1
                    return RunnerInvite(
                        pairingID: "p_\(box.made)", name: name, token: "core.example/FP.SECRET",
                        expiresAt: t0.addingTimeInterval(900))
                },
                status: { _ in box.status },
                withdraw: { id in
                    if let e = box.failWithdraw { throw e }
                    box.withdrawn.append(id)
                },
                runnerNames: { box.names }),
            pasteboard: board)
    }

    @Test func theCommandHasNoToken() async {
        let m = make(Box())
        await m.create(name: "oracle")
        #expect(m.phase == .waiting)
        #expect(
            m.command
                == "sudo sh -c \"$(curl -fsSL https://github.com/AinkradHQ/AinkradCore/releases/latest/download/get.sh)\" sh --runner --invite -"
        )
        #expect(m.command?.contains("SECRET") == false)
    }

    @Test func fifteenMinutesCountDownThenTheInviteIsOver() async {
        let m = make(Box())
        await m.create(name: "oracle")
        #expect(m.secondsLeft(now: t0) == 900)
        #expect(RunnerInviteModel.clock(m.secondsLeft(now: t0.addingTimeInterval(1))) == "14:59")
        m.tick(now: t0.addingTimeInterval(899))
        #expect(m.phase == .waiting)
        m.tick(now: t0.addingTimeInterval(900))
        #expect(m.phase == .expired && m.secondsLeft(now: t0.addingTimeInterval(901)) == 0)
    }

    @Test func waitingBecomesConnectedWhenTheRunnerShowsUp() async {
        let box = Box()
        let m = make(box)
        await m.create(name: "oracle")
        await m.poll()
        #expect(m.phase == .waiting)
        box.names = ["old", "oracle"]
        await m.poll()
        #expect(m.phase == .connected("oracle") && m.done)
    }

    @Test func aClaimedInviteIsConnectedWithTheNewRunnersName() async {
        let box = Box()
        let m = make(box)
        await m.create(name: "linux-runner")
        box.status = "approved"
        box.names = ["old", "Oracle VPS"]
        await m.poll()
        #expect(m.phase == .connected("Oracle VPS"))
    }

    @Test func withdrawTakesItBack() async {
        let box = Box()
        let m = make(box)
        await m.create(name: "oracle")
        await m.withdraw()
        #expect(box.withdrawn == ["p_1"] && m.phase == .withdrawn)
        await m.again(name: "oracle")
        #expect(m.phase == .waiting && box.made == 2)
    }

    @Test func aWithdrawTheCoreCannotReachLeavesItLive() async {
        let box = Box()
        box.failWithdraw = CoreError.offline("down")
        let m = make(box)
        await m.create(name: "oracle")
        await m.withdraw()
        #expect(m.phase == .waiting && m.error != nil)
        #expect(await m.requestClose() == false)
    }

    @Test func closingWithdrawsALiveInviteAndClearsTheCopy() async {
        let box = Box()
        let board = Board()
        let m = make(box, board: board)
        await m.create(name: "oracle")
        m.copy()
        #expect(board.text?.contains("SECRET") == true)
        #expect(await m.requestClose())
        #expect(box.withdrawn == ["p_1"] && board.text == nil)
    }

    @Test func theTokenIsNeverInADescription() async {
        let m = make(Box())
        await m.create(name: "oracle")
        #expect(!"\(String(describing: m.invite))".contains("SECRET"))
        #expect(!String(reflecting: m.invite as Any).contains("SECRET"))
        var dumped = ""
        dump(m.invite, to: &dumped)
        #expect(!dumped.contains("SECRET"))
    }
}
