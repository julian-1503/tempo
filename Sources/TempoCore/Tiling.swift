/// A rectangle in screen coordinates. (TempoCore stays free of CoreGraphics; the shell
/// converts to/from CGRect.)
public struct Frame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Direction in which `.tiles` arranges its N windows.
public enum Orientation: Equatable, Sendable {
    case horizontal  // side-by-side columns
    case vertical    // stacked rows
}

/// The tiling layout within a single workspace.
public enum TilingMode: Equatable, Sendable {
    case tiles(Orientation)
    case accordion
}

/// Computes window frames for a workspace's tiling layout.
public struct Tiler {
    public init() {}

    public func layout(count: Int, in area: Frame, mode: TilingMode) -> [Frame] {
        guard count > 0 else { return [] }
        switch mode {
        case .accordion:
            return Array(repeating: area, count: count)
        case .tiles(let orientation):
            switch orientation {
            case .horizontal:
                let width = area.width / Double(count)
                return (0..<count).map { index in
                    Frame(x: area.x + Double(index) * width, y: area.y,
                          width: width, height: area.height)
                }
            case .vertical:
                let height = area.height / Double(count)
                return (0..<count).map { index in
                    Frame(x: area.x, y: area.y + Double(index) * height,
                          width: area.width, height: height)
                }
            }
        }
    }
}
