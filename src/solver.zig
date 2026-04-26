const rl = @import("raylib");

pub const ScaleState = enum { balanced, left_leaning, right_leaning };
pub const CoinState = enum { unknown, safe, counterfeit };
pub const CounterfeitCoinType = enum { heavier, lighter, unknown };

pub const Coin = struct {
    //
};

const SolverState = union(enum(u8)) {
    start = null,
};

pub fn solveKnown(coins: []const Coin, counterfeit_type: CounterfeitCoinType) void {
    _ = coins;
    _ = counterfeit_type;
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

pub const NodeState = enum { neutral, processing, safe, counterfeit };

pub const Node = struct {
    x: f32,
    y: f32,
    state: NodeState,

    pub fn toVec(self: Node) rl.Vector2 {
        return .init(self.x, self.y);
    }

    pub fn init(x: f32, y: f32) Node {
        return .{ .x = x, .y = y, .state = .neutral };
    }
};
