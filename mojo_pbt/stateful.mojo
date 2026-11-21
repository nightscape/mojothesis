from mojo_pbt.core import Status, TestCase
from mojo_pbt.runner import run_test
from mojo_pbt.strategies import continue_coin, integers


trait StateMachine(Deinitable, Movable):
    """A model and a system under test, driven by numbered rules."""

    comptime RULE_COUNT: Int

    def __init__(out self) raises:
        ...

    def rule_name(self, i: Int) -> String:
        ...

    def precondition(self, i: Int) -> Bool:
        """Whether rule i is applicable in the current state."""
        ...

    def rule(mut self, i: Int, mut tc: TestCase) raises:
        """Runs rule i; draws its arguments with `tc.any`."""
        ...

    def check_invariants(self) raises:
        ...


def machine_property[M: StateMachine, max_steps: Int](mut tc: TestCase) raises:
    """One run of `M`; on the final replay prints each executed step and
    appends the step names to the failure message."""
    var machine = M()
    var rules = integers(0, M.RULE_COUNT - 1)
    var steps = 0
    var trace = List[String]()
    try:
        machine.check_invariants()
        while continue_coin(tc, steps, 0, max_steps):
            steps += 1
            var i = rules.draw(tc)
            # Skipping keeps the case valid, so the shrinker may zero any index.
            if not machine.precondition(i):
                continue
            if tc.print_results:
                var name = machine.rule_name(i)
                print("step:", name)
                trace.append(name^)
            machine.rule(i, tc)
            machine.check_invariants()
    except e:
        if tc.print_results and tc.status == Status.UNDECIDED:
            raise Error(e, "\nsteps: ", ", ".join(trace))
        raise e^


def run_state_machine[M: StateMachine, max_steps: Int = 50](
    seed: UInt64 = 0, max_examples: Int = 100
) raises:
    """Runs random rule sequences of at most `max_steps` steps against `M`.
    Errors as `run_test`; a failure's message ends with its shrunk step names."""
    if max_steps <= 0:
        raise Error("InvalidArgument: max_steps must be positive, got ", max_steps)
    if M.RULE_COUNT <= 0:
        raise Error("InvalidArgument: RULE_COUNT must be positive, got ", M.RULE_COUNT)
    run_test[machine_property[M, max_steps]](seed, max_examples)
