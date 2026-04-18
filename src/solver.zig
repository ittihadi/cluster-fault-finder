const CounterfeitCoinType = enum { heavier, lighter, unknown };
const CoinState = enum { unknown, safe, counterfeit };

const SolverState = union(enum(u8)) {
    start = null,
};

pub fn solveKnown() void {
    const state: SolverState = .start;
    while (true) {
        switch (state) {
            .start => {
                unreachable;
            },
            else => unreachable,
        }
    }
}
