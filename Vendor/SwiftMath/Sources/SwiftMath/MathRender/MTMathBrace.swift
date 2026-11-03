import Foundation

/// A native `\underbrace` / `\overbrace`. Scripts are centered limits, and
/// belong to this atom rather than the last atom of the braced expression.
public class MTMathBrace: MTMathAtom {
    public var innerList: MTMathList?
    public var isOver = false

    override init() {
        super.init()
        type = .brace
    }

    init(_ brace: MTMathBrace?) {
        super.init(brace)
        type = .brace
        innerList = MTMathList(brace?.innerList)
        isOver = brace?.isOver ?? false
    }

    override public var finalized: MTMathAtom {
        let result = super.finalized as! MTMathBrace
        result.innerList = result.innerList?.finalized
        return result
    }
}
