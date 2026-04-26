const std = @import("std");
const rl = @import("raylib");
const NodeCollection = @import("NodeCollection.zig");

pub const CompareResult = enum { equal, left_slower, right_slower };
pub const NodeState = enum { neutral, suspect_a, suspect_b, safe, counterfeit };
pub const SolveStep = struct {
    id: u32,
    step: union(enum(u8)) {
        unsolvable: void,
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

/// Returns a slice owned by the caller
pub fn solve(nodes: *NodeCollection, gpa: std.mem.Allocator, start: usize, end: usize, step: u32) error{OutOfMemory}![]SolveStep {
    var steps: std.ArrayList(SolveStep) = .empty;

    const count = end - start;
    if (count == 1) {
        try steps.append(gpa, .{ .id = step, .step = .unsolvable });
        return steps.toOwnedSlice(gpa);
    }

    var check_group_size = @divFloor(count, 3);
    if (@mod(count, 3) == 2) {
        check_group_size += 1;
    }

    const lhs = nodes.array_list.items[start .. start + check_group_size];
    const rhs = nodes.array_list.items[start + check_group_size .. start + check_group_size + check_group_size];

    const res = compare(lhs, rhs);
    // TODO: Record comparison steps

    // Check base case
    if (count == 2) {
        switch (res) {
            // Shouldn't be able to happen if there has to be ONE faulty node
            .equal => try steps.append(gpa, .{ .id = step + 1, .step = .unsolvable }),
            // Left node is faulty
            .left_slower => try steps.append(gpa, .{ .id = step + 1, .step = .{ .found_at_index = start } }),
            // Right node is faulty
            .right_slower => try steps.append(gpa, .{ .id = step + 1, .step = .{ .found_at_index = start + 1 } }),
        }
    } else if (count == 3) {
        switch (res) {
            // Assume last node is faulty
            .equal => try steps.append(gpa, .{ .id = step + 1, .step = .{ .found_at_index = start + 2 } }),
            // Left node is faulty
            .left_slower => try steps.append(gpa, .{ .id = step + 1, .step = .{ .found_at_index = start } }),
            // Right node is faulty
            .right_slower => try steps.append(gpa, .{ .id = step + 1, .step = .{ .found_at_index = start + 1 } }),
        }
    } else {
        const more_steps = switch (res) {
            // Check the third group
            .equal => try solve(nodes, gpa, start + check_group_size + check_group_size, end, step + 1),
            // Check the first group
            .left_slower => try solve(nodes, gpa, start, start + check_group_size, step + 1),
            // Check the second group
            .right_slower => try solve(nodes, gpa, start + check_group_size, start + check_group_size + check_group_size, step + 1),
        };
        try steps.appendSlice(gpa, more_steps);
        gpa.free(more_steps);
    }

    return steps.toOwnedSlice(gpa);
}

/// This function is a black box in actuality, implementation here has to not matter to the algorithm as long as it's accurate
fn compare(lhs: []Node, rhs: []Node) CompareResult {
    var lhs_faulty = false;
    var rhs_faulty = false;
    for (lhs, rhs) |node_l, node_r| {
        if (node_l.faulty) {
            lhs_faulty = true;
            break;
        } else if (node_r.faulty) {
            rhs_faulty = true;
            break;
        }
    }
    if (lhs_faulty) {
        return .left_slower;
    } else if (rhs_faulty) {
        return .right_slower;
    } else {
        return .equal;
    }
}
