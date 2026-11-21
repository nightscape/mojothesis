from std.testing import assert_equal, assert_raises, assert_true, TestSuite

from mojothesis.core import Random, TestCase
from mojothesis.runner import run_test
from mojothesis.strategies import filter_, integers, lists

comptime SEEDS = 20


def draw_int(lo: Int, hi: Int, k: UInt64) raises -> Int:
    var tc = TestCase.for_choices([k])
    return integers(lo, hi).draw(tc)


def distance(x: Int, target: Int) -> UInt64:
    return UInt64(x) - UInt64(target) if x >= target else UInt64(target) - UInt64(x)


def check_integers(lo: Int, hi: Int, mut rng: Random) raises:
    """Every choice maps into [lo, hi]; choice 0 is the value closest to 0;
    distance from it never decreases with the choice; small ranges are hit
    exactly once per value."""
    var n = UInt64(hi) - UInt64(lo)
    var target = min(max(0, lo), hi)
    assert_equal(draw_int(lo, hi, 0), target)
    var ks: List[UInt64] = [0, 1, 2, 3, n // 2, n - 1, rng.below_or_equal(n)]
    for k in ks:
        if k >= n:
            continue
        var a = draw_int(lo, hi, k)
        var b = draw_int(lo, hi, k + 1)
        assert_true(lo <= a <= hi and lo <= b <= hi, String(lo, " ", hi, " ", k))
        assert_true(distance(a, target) <= distance(b, target), String(lo, " ", hi, " ", k))
    if n <= 64:
        var seen = List[Int]()
        for k in range(Int(n) + 1):
            var x = draw_int(lo, hi, UInt64(k))
            assert_true(lo <= x <= hi and x not in seen, String(lo, " ", hi, " ", k))
            seen.append(x)


def test_integers_map_choices_into_range_nearest_zero_first() raises:
    """Covers the full-range wrap and the shrink-toward-zero encoding."""
    var rng = Random(1)
    var fixed: List[Tuple[Int, Int]] = [
        (Int.MIN, Int.MAX), (Int.MIN, Int.MIN), (Int.MAX, Int.MAX), (Int.MIN, 0),
        (-100, 100), (-100, 5), (-5, 100), (3, 9), (-9, -3), (0, 0),
    ]
    for t in fixed:
        check_integers(t[0], t[1], rng)
    for _ in range(200):
        var a = Int(rng.next())
        var b = Int(rng.next())
        check_integers(min(a, b), max(a, b), rng)
        var lo = Int(rng.below_or_equal(60)) - 30
        check_integers(lo, lo + Int(rng.below_or_equal(40)), rng)


def test_invalid_arguments_raise() raises:
    var rng = Random(2)
    var fixed_ints: List[Tuple[Int, Int]] = [(1, 0), (0, -1), (Int.MAX, Int.MIN)]
    for _ in range(50):
        var a = Int(rng.next())
        var b = Int(rng.next())
        if a != b:
            fixed_ints.append((max(a, b), min(a, b)))
    for t in fixed_ints:
        with assert_raises(contains="InvalidArgument"):
            _ = integers(t[0], t[1])
    var bad_sizes: List[Tuple[Int, Int]] = [(1, 0), (-1, 5), (Int.MAX, 0)]
    for _ in range(50):
        var lo = Int(rng.below_or_equal(100))
        bad_sizes.append((lo + 1 + Int(rng.below_or_equal(100)), lo))
    for t in bad_sizes:
        with assert_raises(contains="InvalidArgument"):
            _ = lists(integers(0, 1), t[0], t[1])
    var bad_examples: List[Int] = [0, -1, Int.MIN]
    for n in bad_examples:
        with assert_raises(contains="InvalidArgument"):
            run_test[half_rejected](0, n)


def always_rejects(mut tc: TestCase) raises:
    tc.assume(tc.any(integers(0, 1000)) > 5000)


def above_5000(x: Int) -> Bool:
    return x > 5000


def filter_never_passes(mut tc: TestCase) raises:
    _ = tc.any(filter_[above_5000](integers(0, 1000)))


def always_overruns(mut tc: TestCase) raises:
    _ = tc.any(lists(integers(0, 1), 9000))


def half_rejected(mut tc: TestCase) raises:
    tc.assume(tc.any(integers(0, 1000)) > 500)


def test_unsatisfiable_raises_only_without_valid_cases() raises:
    for seed in range(SEEDS):
        with assert_raises(contains="Unsatisfiable"):
            run_test[always_rejects](UInt64(seed))
        with assert_raises(contains="Unsatisfiable"):
            run_test[filter_never_passes](UInt64(seed))
        with assert_raises(contains="Unsatisfiable"):
            run_test[always_overruns](UInt64(seed))
        run_test[half_rejected](UInt64(seed))


def fails_except_on_replay(mut tc: TestCase) raises:
    if tc.any(integers(0, 100)) > 10 and not tc.print_results:
        raise Error("fails only while searching")


def rejects_on_replay(mut tc: TestCase) raises:
    tc.assume(not tc.print_results)
    if tc.any(integers(0, 100)) > 10:
        raise Error("fails only while searching")


def test_flaky_failure_raises() raises:
    """The replay is the only run with print_results set, which makes the
    property deterministically flaky."""
    for seed in range(SEEDS):
        with assert_raises(contains="Flaky"):
            run_test[fails_except_on_replay](UInt64(seed))
        with assert_raises(contains="Flaky"):
            run_test[rejects_on_replay](UInt64(seed))


def swallow_then_draw(mut tc: TestCase) raises:
    try:
        tc.assume(False)
    except:
        pass
    _ = tc.any(integers(0, 100))


def swallow_then_return(mut tc: TestCase) raises:
    try:
        tc.assume(False)
    except:
        pass


def swallow_then_fail(mut tc: TestCase) raises:
    try:
        tc.assume(False)
    except:
        pass
    raise Error("assertion after swallowed StopTest")


def swallow_on_replay_then_draw(mut tc: TestCase) raises:
    if tc.any(integers(0, 100)) <= 10:
        return
    if not tc.print_results:
        raise Error("fails while searching")
    try:
        tc.reject()
    except:
        pass
    _ = tc.any(integers(0, 100))


def test_caught_stop_test_is_reported() raises:
    """Includes the final replay, which runs outside the search loop."""
    for seed in range(SEEDS):
        with assert_raises(contains="Frozen"):
            run_test[swallow_on_replay_then_draw](UInt64(seed))
        with assert_raises(contains="Frozen"):
            run_test[swallow_then_draw](UInt64(seed))
        with assert_raises(contains="Frozen"):
            run_test[swallow_then_return](UInt64(seed))
        with assert_raises(contains="Frozen"):
            run_test[swallow_then_fail](UInt64(seed))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
