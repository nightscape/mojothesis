comptime STOP_TEST = "StopTest"
"""The message of the Error that ends a run once its status is decided."""


@fieldwise_init
struct Status(Equatable, TrivialRegisterPassable, Writable):
    var value: Int

    comptime UNDECIDED = Status(-1)
    comptime OVERRUN = Status(0)
    comptime INVALID = Status(1)
    comptime VALID = Status(2)
    comptime INTERESTING = Status(3)


@fieldwise_init
struct Random(Copyable, TrivialRegisterPassable):
    """SplitMix64."""

    var state: UInt64

    def next(mut self) -> UInt64:
        self.state += 0x9E3779B97F4A7C15
        var z = self.state
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) * 0x94D049BB133111EB
        return z ^ (z >> 31)

    def below_or_equal(mut self, n: UInt64) -> UInt64:
        # shortcut: modulo bias for large n, switch to rejection sampling if
        # the distribution ever matters.
        if n == UInt64.MAX:
            return self.next()
        return self.next() % (n + 1)

    def unit(mut self) -> Float64:
        return Float64(self.next() >> 11) * (1.0 / 9007199254740992.0)


struct TestCase(Movable):
    """One run of a property: replays `prefix`, then draws from `random`."""

    var prefix: List[UInt64]
    var random: Random
    var max_size: Int
    var choices: List[UInt64]
    var status: Status
    var print_results: Bool

    def __init__(
        out self,
        var prefix: List[UInt64],
        random: Random,
        max_size: Int,
        print_results: Bool = False,
    ):
        self.prefix = prefix^
        self.random = random
        self.max_size = max_size
        self.choices = []
        self.status = Status.UNDECIDED
        self.print_results = print_results

    @staticmethod
    def for_choices(choices: List[UInt64], print_results: Bool = False) -> TestCase:
        return TestCase(
            choices.copy(), Random(0), len(choices), print_results
        )

    def choice(mut self, n: UInt64) raises -> UInt64:
        """Returns an integer in [0, n]; smaller is simpler."""
        return self._make_choice(n, self.random.below_or_equal(n))

    def weighted(mut self, p: Float64) raises -> Bool:
        """Returns True with probability p."""
        if p <= 0:
            return self.forced_choice(0) == 1
        if p >= 1:
            return self.forced_choice(1) == 1
        return self._make_choice(1, UInt64(1 if self.random.unit() <= p else 0)) == 1

    def forced_choice(mut self, n: UInt64) raises -> UInt64:
        """Records n as a choice without drawing it."""
        self._check_open()
        if len(self.choices) >= self.max_size:
            self._mark_status(Status.OVERRUN)
        self.choices.append(n)
        return n

    def reject(mut self) raises:
        self._mark_status(Status.INVALID)

    def assume(mut self, precondition: Bool) raises:
        if not precondition:
            self.reject()

    def _mark_status(mut self, status: Status) raises:
        """Ends the run with `status`; the runner recognises the raise by `self.status`."""
        self._check_open()
        self.status = status
        raise Error(STOP_TEST)

    def _check_open(self) raises:
        if self.status != Status.UNDECIDED:
            raise Error(
                "Frozen: TestCase used after its run ended; do not catch"
                " the StopTest raised by reject/assume/overrun"
            )

    def _make_choice(mut self, n: UInt64, random_value: UInt64) raises -> UInt64:
        # random_value is drawn eagerly; only used once the prefix is exhausted.
        self._check_open()
        if len(self.choices) >= self.max_size:
            self._mark_status(Status.OVERRUN)
        var result: UInt64
        if len(self.choices) < len(self.prefix):
            result = self.prefix[len(self.choices)]
        else:
            result = random_value
        self.choices.append(result)
        if result > n:
            self._mark_status(Status.INVALID)
        return result

    def any[S: Strategy](mut self, strategy: S) raises -> S.Value:
        """Draws from `strategy`; prints the value on the final replay."""
        var value = strategy.draw(self)
        if self.print_results:
            print("any(...):", value)
        return value^


comptime Drawable = Copyable & Deinitable & Writable
"""What a strategy can produce: copied into results, printed on failure."""


trait Strategy(Copyable, Deinitable):
    comptime Value: Drawable

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        ...
