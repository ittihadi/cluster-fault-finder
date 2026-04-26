const std = @import("std");
const rl = @import("raylib");
const NodeCollection = @import("NodeCollection.zig");

pub const NodeState = enum { neutral, suspect_a, suspect_b, safe, counterfeit };
pub const SolveStep = struct {
    id: u32,
    step: union(enum(u8)) {
        found_at_index: usize,
    },
};

pub const Node = struct {
    x: f32,
    y: f32,
    state: NodeState,
    faulty: bool,

    pub fn toVec(self: Node) rl.Vector2 {
        return .init(self.x, self.y);
    }

    pub fn init(x: f32, y: f32) Node {
        return .{ .x = x, .y = y, .state = .neutral, .faulty = false };
    }
};

pub fn solve(nodes: *NodeCollection) []SolveStep {
    _ = nodes;
    return &[0]SolveStep{};
}
