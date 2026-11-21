from std.testing import assert_equal, assert_true, TestSuite

from mojothesis.core import TestCase, Strategy
from mojothesis.runner import TestingState
from mojothesis.strategies import booleans, filter_, integers, lists, map_, pair

comptime SEEDS = 20


def big_sum_lists() raises -> type_of(lists(integers(0, 10000))):
    return lists(integers(0, 10000))


def sum_at_most_1000(mut tc: TestCase) raises:
    var total = 0
    for x in tc.any(big_sum_lists()):
        total += x
    assert_true(total <= 1000)


def times_two(x: Int) -> Int:
    return x * 2


def not_div_by_3(x: Int) -> Bool:
    return x % 3 != 0


def composed() raises -> type_of(pair(filter_[not_div_by_3](map_[times_two](integers(0, 1000))), booleans())):
    return pair(filter_[not_div_by_3](map_[times_two](integers(0, 1000))), booleans())


def small_or_false(mut tc: TestCase) raises:
    var v = tc.any(composed())
    assert_true(v[0] <= 50 or not v[1])


def shrink[test: def(mut TestCase) raises thin -> None](seed: UInt64) raises -> List[UInt64]:
    var state = TestingState[test](seed, 1000)
    state.generate()
    assert_true(Bool(state.result), "no failure found")
    state.shrink()
    return state.result.value().copy()


def replay[S: Strategy](strategy: S, choices: List[UInt64]) raises -> S.Value:
    var tc = TestCase.for_choices(choices)
    return strategy.draw(tc)


def test_sum_shrinks_to_single_1001() raises:
    """For every seed, the shrinker finds exactly [1001]."""
    for seed in range(SEEDS):
        var result = replay(big_sum_lists(), shrink[sum_at_most_1000](UInt64(seed)))
        assert_equal(result, [1001])


def test_map_filter_pair_shrinks_to_minimum() raises:
    """Smallest 2x > 50 with 2x % 3 != 0 is 52, paired with True."""
    for seed in range(SEEDS):
        var v = replay(composed(), shrink[small_or_false](UInt64(seed)))
        assert_equal(v[0], 52)
        assert_true(v[1])


def len_below[max_size: Int](mut tc: TestCase) raises:
    assert_true(len(tc.any(lists(integers(0, 10), 0, max_size))) < max_size)


def test_lists_reach_max_size_inclusive() raises:
    """The shortest failing list has exactly max_size elements; max_size=1 is
    the case where only [] was reachable."""
    comptime for max_size in [1, 2, 5]:
        for seed in range(SEEDS):
            var l = replay(lists(integers(0, 10), 0, max_size), shrink[len_below[max_size]](UInt64(seed)))
            assert_equal(len(l), max_size)
            for x in l:
                assert_equal(x, 0)


def abs_below_10[lo: Int, hi: Int](mut tc: TestCase) raises:
    var x = tc.any(integers(lo, hi))
    assert_true(-10 < x < 10)


def test_signed_ranges_shrink_toward_zero() raises:
    """(-100, 100) is the range that shrank to -100; the others take the
    one-sided and asymmetric branches of the encoding."""
    comptime for r in [(-100, 100, 10), (-5, 100, 10), (-100, 5, -10), (-100, -1, -10), (Int.MIN, Int.MAX, 10)]:
        for seed in range(SEEDS):
            var x = replay(integers(r[0], r[1]), shrink[abs_below_10[r[0], r[1]]](UInt64(seed)))
            assert_equal(x, r[2])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
