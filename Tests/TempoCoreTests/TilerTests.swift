import Testing
@testable import TempoCore

@Suite("Tiler")
struct TilerTests {
    let tiler = Tiler()
    let area = Frame(x: 0, y: 0, width: 900, height: 600)

    @Test("no windows yields no frames")
    func empty() {
        #expect(tiler.layout(count: 0, in: area, mode: .tiles(.horizontal)) == [])
    }

    @Test("a single window fills the area")
    func single() {
        #expect(tiler.layout(count: 1, in: area, mode: .tiles(.horizontal)) == [area])
    }

    @Test("horizontal tiles split into equal side-by-side columns")
    func tilesColumns() {
        #expect(tiler.layout(count: 3, in: area, mode: .tiles(.horizontal)) == [
            Frame(x: 0, y: 0, width: 300, height: 600),
            Frame(x: 300, y: 0, width: 300, height: 600),
            Frame(x: 600, y: 0, width: 300, height: 600),
        ])
    }

    @Test("vertical tiles split into equal stacked rows")
    func tilesRows() {
        #expect(tiler.layout(count: 3, in: area, mode: .tiles(.vertical)) == [
            Frame(x: 0, y: 0, width: 900, height: 200),
            Frame(x: 0, y: 200, width: 900, height: 200),
            Frame(x: 0, y: 400, width: 900, height: 200),
        ])
    }

    @Test("accordion stacks every window over the full area")
    func accordionStacks() {
        #expect(tiler.layout(count: 2, in: area, mode: .accordion) == [area, area])
    }
}
