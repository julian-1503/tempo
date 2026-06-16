import Testing
@testable import TempoCore

@Suite("Tiler")
struct TilerTests {
    let tiler = Tiler()
    let area = Frame(x: 0, y: 0, width: 900, height: 600)

    @Test("no windows yields no frames")
    func empty() {
        #expect(tiler.layout(count: 0, in: area, mode: .tiles) == [])
    }

    @Test("a single window fills the area")
    func single() {
        #expect(tiler.layout(count: 1, in: area, mode: .tiles) == [area])
    }

    @Test("tiles splits into equal side-by-side columns")
    func tilesColumns() {
        #expect(tiler.layout(count: 3, in: area, mode: .tiles) == [
            Frame(x: 0, y: 0, width: 300, height: 600),
            Frame(x: 300, y: 0, width: 300, height: 600),
            Frame(x: 600, y: 0, width: 300, height: 600),
        ])
    }

    @Test("accordion stacks every window over the full area")
    func accordionStacks() {
        #expect(tiler.layout(count: 2, in: area, mode: .accordion) == [area, area])
    }
}
