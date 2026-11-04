import CoreGraphics
import Testing

@testable import Shell

struct TileTreeTests {
    private let gap: CGFloat = 12
    private func tree(_ ids: String...) -> TileTree {
        var t = TileTree()
        for id in ids { t.open(id) }
        return t
    }
    private func layout(_ t: TileTree, width: CGFloat = 1500, mins: [String: CGFloat] = [:]) -> TileLayout {
        t.layout(
            minWidth: { mins[$0] ?? 340 }, container: CGSize(width: width, height: 700), gap: gap, minHeight: 560)
    }

    @Test func openingAppendsEqualColumns() {
        let l = layout(tree("a", "b", "c"))
        #expect(!l.isStrip && l.seams.count == 2)
        #expect(l.frames["a"]!.width == l.frames["c"]!.width)
        #expect(abs(l.frames["c"]!.maxX - 1500) < 0.5)
        var t = tree("a")
        t.open("a")
        #expect(t.leaves == ["a"])
    }

    @Test func stripStartsWhenMinimumsDoNotFit() {
        let t = tree("a", "b", "c", "d")
        let need: CGFloat = 340 * 4 + gap * 3
        #expect(!layout(t, width: need).isStrip)
        let l = layout(t, width: need - 1)
        #expect(l.isStrip && l.frames.values.allSatisfy { $0.width == 340 } && l.contentWidth == need)
    }

    @Test func heightNeverDropsBelowTheMinimum() {
        let l = tree("a").layout(
            minWidth: { _ in 340 }, container: CGSize(width: 900, height: 400), gap: gap, minHeight: 560)
        #expect(l.frames["a"]!.height == 560)
    }

    @Test func aWiderPaneKeepsItsMinimum() {
        let l = layout(tree("a", "b", "c"), width: 1400, mins: ["a": 560])
        #expect(l.frames["a"]!.width >= 560 - 0.01 && abs(l.frames["c"]!.maxX - 1400) < 0.5)
    }

    @Test func dropAlongTheRowJoinsAsAnEqualSibling() {
        var t = tree("a", "b", "c")
        t.drop("c", on: "a", edge: .left)
        #expect(t.leaves == ["c", "a", "b"])
        guard case .split(.horizontal, let f, let kids)? = t.root else {
            Issue.record("not a row")
            return
        }
        #expect(kids.count == 3 && f.allSatisfy { abs($0 - 1.0 / 3) < 0.001 })
    }

    @Test func dropAcrossWrapsTheTargetInAFiftyFiftySplit() {
        var t = tree("a", "b", "c")
        t.drop("c", on: "a", edge: .bottom)
        #expect(t.leaves == ["a", "c", "b"])
        guard case .split(.horizontal, _, let kids)? = t.root, kids.count == 2,
            case .split(.vertical, let f, let col) = kids[0]
        else {
            Issue.record("a was not wrapped")
            return
        }
        #expect(col == [.leaf("a"), .leaf("c")] && f == [0.5, 0.5])
        let l = layout(t)
        #expect(l.frames["a"]!.width == l.frames["c"]!.width && l.frames["c"]!.minY > l.frames["a"]!.maxY)
        #expect(l.seams.contains { $0.axis == .vertical })
    }

    @Test func closingCollapsesASingleChildSplit() {
        var t = tree("a", "b", "c")
        t.drop("c", on: "a", edge: .bottom)
        t.remove("c")
        #expect(t.root == .equalSplit(.horizontal, [.leaf("a"), .leaf("b")]))
        t.remove("a")
        #expect(t.root == .leaf("b"))
        t.remove("b")
        #expect(t.root == nil)
    }

    @Test func aSeamDragKeepsTheTotalAndTenPercent() {
        var t = tree("a", "b", "c")
        let seam = layout(t).seams[0]
        t.resize(seam, gap: gap, position: 100)  // far left: the pane minimum (340 of the row) wins over 10 %
        let l = layout(t)
        #expect(l.frames["a"]!.width >= 340 - 0.01)
        #expect(abs(l.frames["c"]!.maxX - 1500) < 0.5)
        var v = tree("a", "b")
        v.drop("b", on: "a", edge: .bottom)
        let vs = layout(v).seams.first { $0.axis == .vertical }!
        v.resize(vs, gap: gap, position: 0)
        let after = layout(v)
        #expect(abs(after.frames["a"]!.height / (after.frames["a"]!.height + after.frames["b"]!.height) - 0.1) < 0.02)
    }

    @Test func keyboardMovesOnePlace() {
        var t = tree("a", "b", "c")
        let first = t.move("a", step: 1)
        #expect(first && t.leaves == ["b", "a", "c"])
        let off = t.move("c", step: 1)
        #expect(!off)
        let back = t.move("c", step: -1)
        #expect(back && t.leaves == ["b", "c", "a"])
    }

    @Test func dropTargetPicksTheNearHalf() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 400, height: 600), "b": CGRect(x: 412, y: 0, width: 400, height: 600)]
        let left = TileTree.dropTarget(at: CGPoint(x: 450, y: 300), frames: frames, excluding: "a")
        #expect(left?.target == "b" && left?.edge == .left && left?.hint.width == 200)
        let bottom = TileTree.dropTarget(at: CGPoint(x: 600, y: 580), frames: frames, excluding: "a")
        #expect(bottom?.edge == .bottom && bottom?.hint.minY == 300)
        #expect(TileTree.dropTarget(at: CGPoint(x: 200, y: 100), frames: frames, excluding: "a") == nil)
        #expect(TileTree.dropTarget(at: CGPoint(x: 406, y: 100), frames: frames, excluding: "a") == nil)
    }
}
