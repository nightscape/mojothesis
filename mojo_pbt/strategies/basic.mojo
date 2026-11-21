from mojo_pbt.core import TestCase
from mojo_pbt.core import Strategy


struct Integers(Strategy):
    """One choice k per value. k = 0 is the value closest to 0; the distance
    from it never decreases with k, alternating +d, -d while both sides have room.
    Offsets are UInt64 so the full Int range does not wrap."""

    comptime Value = Int
    var target: Int
    var above: UInt64
    var below: UInt64

    def __init__(out self, lo: Int, hi: Int) raises:
        if lo > hi:
            raise Error("InvalidArgument: integers(lo=", lo, ", hi=", hi, ") needs lo <= hi")
        self.target = min(max(0, lo), hi)
        self.above = UInt64(hi) - UInt64(self.target)
        self.below = UInt64(self.target) - UInt64(lo)

    def draw(self, mut tc: TestCase) raises -> Int:
        var k = tc.choice(self.above + self.below)
        var both = min(self.above, self.below)
        var up: Bool
        var dist: UInt64
        if k <= 2 * both:
            up = k % 2 == 1
            dist = (k + 1) // 2
        else:
            up = self.above > self.below
            dist = k - both
        var t = UInt64(self.target)
        return Int(t + dist) if up else Int(t - dist)


@fieldwise_init
struct Booleans(Strategy):
    comptime Value = Bool

    def draw(self, mut tc: TestCase) raises -> Bool:
        return tc.choice(1) == 1


def integers(lo: Int, hi: Int) raises -> Integers:
    return Integers(lo, hi)


def booleans() -> Booleans:
    return Booleans()
