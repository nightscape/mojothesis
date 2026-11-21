from std.testing import assert_equal, assert_raises, TestSuite

from mojothesis.core import TestCase
from mojothesis.stateful import StateMachine, run_state_machine
from mojothesis.strategies import integers

comptime SEEDS = 20


struct StackMachine[drop_at: Int](StateMachine):
    """A List model against a stack that silently drops pushes once it holds
    `drop_at` elements."""

    comptime RULE_COUNT = 2
    comptime PUSH = 0
    var model: List[Int]
    var sut: List[Int]

    def __init__(out self) raises:
        self.model = []
        self.sut = []

    def rule_name(self, i: Int) -> String:
        return "push" if i == Self.PUSH else "pop"

    def precondition(self, i: Int) -> Bool:
        return i == Self.PUSH or len(self.model) > 0

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        if i == Self.PUSH:
            var x = tc.any(integers(0, 100))
            self.model.append(x)
            if len(self.sut) < Self.drop_at:
                self.sut.append(x)
        elif i == 1:
            assert_equal(self.sut.pop(), self.model.pop())
        else:
            raise Error("rule index out of range: ", i)

    def check_invariants(self) raises:
        if self.model != self.sut:
            raise Error("model=", self.model, " sut=", self.sut)


def failure_message[M: StateMachine](seed: UInt64) raises -> String:
    try:
        run_state_machine[M](seed)
    except e:
        return String(e)
    raise Error("no failure found")


def test_buggy_stack_shrinks_to_four_pushes_of_zero() raises:
    """Step deletion and argument shrinking reach the exact minimum: the 4th
    push is the first one the SUT drops."""
    for seed in range(SEEDS):
        assert_equal(
            failure_message[StackMachine[3]](UInt64(seed)),
            "model=[0, 0, 0, 0] sut=[0, 0, 0]\nsteps: push, push, push, push",
        )


def test_correct_machine_never_fails() raises:
    """No false alarms: a stack that never drops matches its model, and no
    rule index beyond RULE_COUNT - 1 is drawn."""
    for seed in range(SEEDS):
        run_state_machine[StackMachine[Int.MAX]](UInt64(seed))


struct StaleFlag(StateMachine):
    """After a pop, the SUT drops the next push."""

    comptime RULE_COUNT = 2
    var model: List[Int]
    var sut: List[Int]
    var stale: Bool

    def __init__(out self) raises:
        self.model = []
        self.sut = []
        self.stale = False

    def rule_name(self, i: Int) -> String:
        return "push" if i == 0 else "pop"

    def precondition(self, i: Int) -> Bool:
        return i == 0 or len(self.model) > 0

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        if i == 0:
            var x = tc.any(integers(0, 100))
            self.model.append(x)
            if not self.stale:
                self.sut.append(x)
            self.stale = False
        else:
            _ = self.model.pop()
            _ = self.sut.pop()
            self.stale = True

    def check_invariants(self) raises:
        if self.model != self.sut:
            raise Error("model=", self.model, " sut=", self.sut)


def test_three_choice_steps_are_deleted() raises:
    """A push step is 3 choices, so reaching the minimum needs span deletion
    of size 3, not only powers of two."""
    for seed in range(SEEDS):
        assert_equal(
            failure_message[StaleFlag](UInt64(seed)),
            "model=[0] sut=[]\nsteps: push, pop, push",
        )


struct StepCounter[fail_at: Int](StateMachine):
    """Fails once `fail_at` steps have run."""

    comptime RULE_COUNT = 1
    var n: Int

    def __init__(out self) raises:
        self.n = 0

    def rule_name(self, i: Int) -> String:
        return "tick"

    def precondition(self, i: Int) -> Bool:
        return True

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        self.n += 1

    def check_invariants(self) raises:
        if self.n >= Self.fail_at:
            raise Error("n=", self.n)


def test_runs_have_at_most_max_steps() raises:
    """With max_steps=3 every length up to 3 is reached and 4 never is."""
    comptime MAX_STEPS = 3
    comptime for fail_at in range(1, MAX_STEPS + 1):
        var trace = List[String]()
        for _ in range(fail_at):
            trace.append("tick")
        for seed in range(SEEDS):
            try:
                run_state_machine[StepCounter[fail_at], MAX_STEPS](UInt64(seed))
                raise Error("no failure for fail_at=", fail_at)
            except e:
                assert_equal(String(e), String("n=", fail_at, "\nsteps: ", ", ".join(trace)))
    for seed in range(SEEDS):
        run_state_machine[StepCounter[MAX_STEPS + 1], MAX_STEPS](UInt64(seed))


struct LastRuleFails(StateMachine):
    """Fails only when the highest rule index runs."""

    comptime RULE_COUNT = 3

    def __init__(out self) raises:
        pass

    def rule_name(self, i: Int) -> String:
        return String("r", i)

    def precondition(self, i: Int) -> Bool:
        return True

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        if i == Self.RULE_COUNT - 1:
            raise Error("last rule ran")

    def check_invariants(self) raises:
        pass


def test_last_rule_index_is_drawn() raises:
    """Rule indices cover RULE_COUNT - 1; the minimum is that single step."""
    for seed in range(SEEDS):
        assert_equal(failure_message[LastRuleFails](UInt64(seed)), "last rule ran\nsteps: r2")


struct BadInitialState(StateMachine):
    """No rule is ever applicable and the initial state breaks the invariant."""

    comptime RULE_COUNT = 2

    def __init__(out self) raises:
        pass

    def rule_name(self, i: Int) -> String:
        return "never"

    def precondition(self, i: Int) -> Bool:
        return False

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        raise Error("rule ran although its precondition was false")

    def check_invariants(self) raises:
        raise Error("initial state invalid")


def test_initial_state_invariants_are_checked() raises:
    """Invariants run before the first step, so an empty trace fails."""
    for seed in range(SEEDS):
        assert_equal(failure_message[BadInitialState](UInt64(seed)), "initial state invalid\nsteps: ")


struct CycleMachine(StateMachine):
    """Exactly one rule is applicable at a time: rule i only when state == i."""

    comptime RULE_COUNT = 4
    var state: Int

    def __init__(out self) raises:
        self.state = 0

    def rule_name(self, i: Int) -> String:
        return String("advance", i)

    def precondition(self, i: Int) -> Bool:
        return i == self.state

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        assert_equal(i, self.state, "rule ran although its precondition was false")
        self.state = (self.state + 1) % Self.RULE_COUNT

    def check_invariants(self) raises:
        pass


def test_inapplicable_steps_are_skipped_not_rejected() raises:
    """Gated rules never run, and drawing one keeps the case valid: with
    max_examples=1 there are only 10 attempts, so rejecting the ~87% of cases
    that draw an inapplicable rule would raise Unsatisfiable."""
    for seed in range(SEEDS):
        run_state_machine[CycleMachine](UInt64(seed))
        run_state_machine[CycleMachine](UInt64(seed), max_examples=1)


struct NoRules(StateMachine):
    comptime RULE_COUNT = 0

    def __init__(out self) raises:
        pass

    def rule_name(self, i: Int) -> String:
        return ""

    def precondition(self, i: Int) -> Bool:
        return True

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        pass

    def check_invariants(self) raises:
        pass


def test_invalid_arguments_raise() raises:
    """Bad max_steps, RULE_COUNT and max_examples are reported, not run."""
    comptime for max_steps in [0, -1, Int.MIN]:
        with assert_raises(contains="InvalidArgument"):
            run_state_machine[CycleMachine, max_steps]()
    with assert_raises(contains="InvalidArgument"):
        run_state_machine[NoRules]()
    with assert_raises(contains="InvalidArgument"):
        run_state_machine[CycleMachine](0, max_examples=0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
