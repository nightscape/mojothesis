from mojo_pbt.core import TestCase
from mojo_pbt.core import Strategy, Drawable


struct Lists[S: Strategy](Strategy):
    """Each element is preceded by a "continue?" coin, so deleting a span of
    choices deletes elements and zeroing a coin truncates the list."""

    comptime Value = List[Self.S.Value]
    var elements: Self.S
    var min_size: Int
    var max_size: Int

    def __init__(out self, var elements: Self.S, min_size: Int, max_size: Int) raises:
        if not 0 <= min_size <= max_size:
            raise Error(
                "InvalidArgument: lists(min_size=", min_size, ", max_size=", max_size,
                ") needs 0 <= min_size <= max_size",
            )
        self.elements = elements^
        self.min_size = min_size
        self.max_size = max_size

    def draw(self, mut tc: TestCase) raises -> List[Self.S.Value]:
        var result = List[Self.S.Value]()
        while continue_coin(tc, len(result), self.min_size, self.max_size):
            result.append(self.elements.draw(tc))
        return result^


def continue_coin(mut tc: TestCase, size: Int, min_size: Int, max_size: Int) raises -> Bool:
    """The "continue?" coin drawn before each element of a sequence of `size`
    elements so far; forced while outside [min_size, max_size)."""
    if size < min_size:
        return tc.forced_choice(1) == 1
    if size >= max_size:
        return tc.forced_choice(0) == 1
    return tc.weighted(0.9)


def lists[S: Strategy](elements: S, min_size: Int = 0, max_size: Int = Int.MAX) raises -> Lists[S]:
    return Lists[S](elements.copy(), min_size, max_size)


@fieldwise_init
struct Map[S: Strategy, To: Drawable, f: def(S.Value) thin -> To](Strategy):
    comptime Value = Self.To
    var source: Self.S

    def draw(self, mut tc: TestCase) raises -> Self.To:
        return Self.f(self.source.draw(tc))


@fieldwise_init
struct Filter[S: Strategy, pred: def(S.Value) thin -> Bool](Strategy):
    comptime Value = Self.S.Value
    var source: Self.S

    def draw(self, mut tc: TestCase) raises -> Self.S.Value:
        var tries = 0
        while True:
            var candidate = self.source.draw(tc)
            if Self.pred(candidate):
                return candidate^
            tries += 1
            if tries == 3:
                tc.reject()


@fieldwise_init
struct Pair[A: Strategy, B: Strategy](Strategy):
    comptime Value = Tuple[Self.A.Value, Self.B.Value]
    var first: Self.A
    var second: Self.B

    def draw(self, mut tc: TestCase) raises -> Tuple[Self.A.Value, Self.B.Value]:
        var a = self.first.draw(tc)
        var b = self.second.draw(tc)
        return (a^, b^)


def map_[S: Strategy, To: Drawable, //, f: def(S.Value) thin -> To](source: S) -> Map[S, To, f]:
    return Map[S, To, f](source.copy())


def filter_[S: Strategy, //, pred: def(S.Value) thin -> Bool](source: S) -> Filter[S, pred]:
    return Filter[S, pred](source.copy())


def pair[A: Strategy, B: Strategy](first: A, second: B) -> Pair[A, B]:
    return Pair[A, B](first.copy(), second.copy())
