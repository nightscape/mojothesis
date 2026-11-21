from std.os import abort

from mojo_pbt.core import Random, Status, TestCase, STOP_TEST

comptime Property = def(mut TestCase) raises thin -> None
comptime BUFFER_SIZE = 8 * 1024


def shortlex_less(a: List[UInt64], b: List[UInt64]) -> Bool:
    if len(a) != len(b):
        return len(a) < len(b)
    for i in range(len(a)):
        if a[i] != b[i]:
            return a[i] < b[i]
    return False


struct TestingState[test: Property]:
    var random: Random
    var max_examples: Int
    var calls: Int
    var valid_test_cases: Int
    var test_is_trivial: Bool
    var result: Optional[List[UInt64]]

    def __init__(out self, seed: UInt64, max_examples: Int):
        self.random = Random(seed)
        self.max_examples = max_examples
        self.calls = 0
        self.valid_test_cases = 0
        self.test_is_trivial = False
        self.result = None

    def test_function(mut self, mut tc: TestCase) raises:
        var stopped = False
        try:
            Self.test(tc)
        except e:
            if tc.status == Status.UNDECIDED:
                tc.status = Status.INTERESTING
            elif String(e) == STOP_TEST:
                stopped = True
            else:
                raise Error("Frozen: property raised after its run ended: ", e)
        if tc.status == Status.UNDECIDED:
            tc.status = Status.VALID
        elif not stopped and tc.status != Status.INTERESTING:
            raise Error("Frozen: property returned normally after catching StopTest")
        self.calls += 1
        if tc.status.value >= Status.INVALID.value and len(tc.choices) == 0:
            self.test_is_trivial = True
        if tc.status.value >= Status.VALID.value:
            self.valid_test_cases += 1
        if tc.status == Status.INTERESTING:
            if not self.result or shortlex_less(tc.choices, self.result.value()):
                self.result = tc.choices.copy()

    def generate(mut self) raises:
        while (
            not self.test_is_trivial
            and not self.result
            and self.valid_test_cases < self.max_examples
            and self.calls < self.max_examples * 10
        ):
            var tc = TestCase([], self.random, BUFFER_SIZE)
            self.test_function(tc)
            self.random = tc.random

    def consider(mut self, choices: List[UInt64]) raises -> Bool:
        if choices == self.result.value():
            return True
        var tc = TestCase.for_choices(choices)
        self.test_function(tc)
        return tc.status == Status.INTERESTING

    def replace(mut self, indices: List[Int], values: List[UInt64]) raises -> Bool:
        var attempt = self.result.value().copy()
        for k in range(len(indices)):
            if indices[k] >= len(attempt):
                return False
            attempt[indices[k]] = values[k]
        return self.consider(attempt)

    def bin_search_replace(mut self, i: Int, j: Int, hi: UInt64) raises:
        """Smallest v in [0, hi] for which setting result[i] = v (and, when
        j >= 0, result[j] += old_i - v) stays interesting."""
        var prev_i = self.result.value()[i]
        var prev_j = self.result.value()[j] if j >= 0 else UInt64(0)

        def attempt(v: UInt64) raises {mut self, prev_i, prev_j, i, j} -> Bool:
            if j < 0:
                return self.replace([i], [v])
            var moved = prev_i - v
            if prev_j > UInt64.MAX - moved:
                return False
            return self.replace([i, j], [v, prev_j + moved])

        var lo = UInt64(0)
        var top = hi
        if attempt(lo):
            return
        while lo + 1 < top:
            var mid = lo + (top - lo) // 2
            if attempt(mid):
                top = mid
            else:
                lo = mid

    def shrink(mut self) raises:
        if not self.result:
            return
        var prev = List[UInt64]()
        while prev != self.result.value():
            prev = self.result.value().copy()
            self._delete_spans()
            self._zero_spans()
            var i = len(self.result.value()) - 1
            while i >= 0:
                self.bin_search_replace(i, -1, self.result.value()[i])
                i -= 1
            self._sort_spans()
            self._redistribute()

    def _delete_spans(mut self) raises:
        var k = 8
        while k > 0:
            var i = len(self.result.value()) - k - 1
            while i >= 0:
                if i >= len(self.result.value()):
                    i -= 1
                    continue
                var cur = self.result.value().copy()
                var attempt = List[UInt64](cur[:i])
                attempt.extend(cur[min(i + k, len(cur)) :])
                if len(attempt) >= len(cur):
                    abort("_delete_spans: deletion did not shorten the sequence")
                if not self.consider(attempt):
                    # Deleting a list element also needs its "continue?" coin
                    # decremented when the element was last.
                    if i > 0 and attempt[i - 1] > 0:
                        attempt[i - 1] -= 1
                        if self.consider(attempt):
                            i += 1
                    i -= 1
            k -= 1

    def _zero_spans(mut self) raises:
        var k = 8
        while k > 1:
            var i = len(self.result.value()) - k
            while i >= 0:
                var indices = List[Int]()
                var zeros = List[UInt64]()
                for j in range(i, i + k):
                    indices.append(j)
                    zeros.append(0)
                if self.replace(indices, zeros):
                    i -= k
                else:
                    i -= 1
            k //= 2

    def _sort_spans(mut self) raises:
        var k = 8
        while k > 1:
            var i = len(self.result.value()) - k - 1
            while i >= 0:
                if i + k <= len(self.result.value()):
                    var attempt = self.result.value().copy()
                    var span = List[UInt64](attempt[i : i + k])
                    sort(span)
                    for j in range(k):
                        attempt[i + j] = span[j]
                    _ = self.consider(attempt)
                i -= 1
            k //= 2

    def _redistribute(mut self) raises:
        for k in [2, 1]:
            var i = len(self.result.value()) - 1 - k
            while i >= 0:
                var j = i + k
                if j < len(self.result.value()):
                    var r = self.result.value().copy()
                    if r[i] > r[j]:
                        _ = self.replace([j, i], [r[i], r[j]])
                    if j < len(self.result.value()) and self.result.value()[i] > 0:
                        self.bin_search_replace(i, j, self.result.value()[i])
                i -= 1


def run_test[test: Property](seed: UInt64 = 0, max_examples: Int = 100) raises:
    """Raises the property's error, after printing the minimal drawn values.
    Raises Unsatisfiable when no case was valid, Flaky when the minimal failing
    case does not fail on replay."""
    if max_examples <= 0:
        raise Error("InvalidArgument: max_examples must be positive, got ", max_examples)
    var state = TestingState[test](seed, max_examples)
    state.generate()
    if not state.result:
        if state.valid_test_cases == 0:
            raise Error(
                "Unsatisfiable: all ", state.calls,
                " cases were rejected or overran; no valid example ran",
            )
        return
    state.shrink()
    var tc = TestCase.for_choices(state.result.value(), print_results=True)
    var returned_after_stop = False
    try:
        test(tc)
        returned_after_stop = tc.status != Status.UNDECIDED
    except e:
        if tc.status == Status.UNDECIDED:
            raise e^
        if String(e) != STOP_TEST:
            raise Error("Frozen: property raised after its run ended: ", e)
    if returned_after_stop:
        raise Error("Frozen: property returned normally after catching StopTest")
    raise Error("Flaky: the minimal failing case did not fail on replay")
