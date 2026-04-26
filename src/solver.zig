const std = @import("std");
const rl = @import("raylib");
const NodeCollection = @import("NodeCollection.zig");

pub const CompareResult = enum { equal, left_slower, right_slower };
pub const NodeState = enum { neutral, suspect_a, suspect_b, safe, counterfeit };
pub const SolveStep = struct {
    id: u32,
    step: union(enum(u8)) {
        incorrect_input: void,
        found_at_index: usize,
        change_state: struct {
            index: usize,
            from: NodeState,
            to: NodeState,
        },
        start_compare: void,
        compare_size: usize,
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

    if (nodes.count() == 1) {
        try steps.append(gpa, .{ .id = step, .step = .incorrect_input });
        return steps.toOwnedSlice(gpa);
    }

    // Assume last node is counterfeit
    const count = end - start;
    if (count == 1) {
        try recordStateChangeSlice(&steps, gpa, nodes.array_list.items[start..end], start, step, .counterfeit);
        try steps.append(gpa, .{ .id = step, .step = .{ .found_at_index = start } });
        return steps.toOwnedSlice(gpa);
    }

    var check_group_size = @divFloor(count, 3);
    if (@mod(count, 3) == 2) {
        check_group_size += 1;
    }

    const lhs = nodes.array_list.items[start .. start + check_group_size];
    const rhs = nodes.array_list.items[start + check_group_size .. start + check_group_size + check_group_size];
    const rem = nodes.array_list.items[start + check_group_size + check_group_size .. end];

    // Record steps
    try steps.append(gpa, .{ .id = step, .step = .{ .compare_size = check_group_size } });
    try recordStateChangeSlice(&steps, gpa, lhs, start, step, .suspect_a);
    try recordStateChangeSlice(&steps, gpa, rhs, start + check_group_size, step, .suspect_b);
    try recordStateChangeSlice(&steps, gpa, rem, start + check_group_size + check_group_size, step, .neutral);
    try steps.append(gpa, .{ .id = step, .step = .start_compare });

    const res: CompareResult = compare(lhs, rhs);

    // Record steps
    switch (res) {
        .equal => {
            // Mark first group safe
            try recordStateChangeSlice(&steps, gpa, lhs, start, step + 1, .safe);

            // Mark second group safe
            try recordStateChangeSlice(&steps, gpa, rhs, start + check_group_size, step + 1, .safe);
        },
        .left_slower => {
            // Mark second group safe
            try recordStateChangeSlice(&steps, gpa, rhs, start + check_group_size, step + 1, .safe);

            // Mark third group safe
            try recordStateChangeSlice(&steps, gpa, rem, start + check_group_size + check_group_size, step + 1, .safe);
        },
        .right_slower => {
            // Mark first group safe
            try recordStateChangeSlice(&steps, gpa, lhs, start, step + 1, .safe);

            // Mark third group safe
            try recordStateChangeSlice(&steps, gpa, rem, start + check_group_size + check_group_size, step + 1, .safe);
        },
    }

    // Check base case
    if (check_group_size == 1) {
        switch (res) {
            .equal => {
                switch (count) {
                    // Shouldn't be able to happen if there has to be ONE faulty node
                    2 => try steps.append(gpa, .{ .id = step + 2, .step = .incorrect_input }),
                    // Do one more check
                    3, 4 => {
                        // -- Actual recurse here --
                        const more_steps = try solve(nodes, gpa, start + 2, end, step + 2);
                        try steps.appendSlice(gpa, more_steps);
                        gpa.free(more_steps);
                    },
                    else => unreachable,
                }
            },
            // Left node is faulty
            .left_slower => {
                try recordStateChangeSlice(&steps, gpa, lhs, start, step + 2, .counterfeit);
                try steps.append(gpa, .{ .id = step + 2, .step = .{ .found_at_index = start } });
            },
            // Right node is faulty
            .right_slower => {
                try recordStateChangeSlice(&steps, gpa, rhs, start + 1, step + 2, .counterfeit);
                try steps.append(gpa, .{ .id = step + 2, .step = .{ .found_at_index = start + 1 } });
            },
        }
    } else {
        // -- Actual recurse here --
        const more_steps = switch (res) {
            // Check the third group
            .equal => try solve(nodes, gpa, start + check_group_size + check_group_size, end, step + 2),
            // Check the first group
            .left_slower => try solve(nodes, gpa, start, start + check_group_size, step + 2),
            // Check the second group
            .right_slower => try solve(nodes, gpa, start + check_group_size, start + check_group_size + check_group_size, step + 2),
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

fn recordStateChangeSlice(
    steps: *std.ArrayList(SolveStep),
    gpa: std.mem.Allocator,
    nodes: []Node,
    start_idx: usize,
    step: u32,
    to: NodeState,
) error{OutOfMemory}!void {
    for (nodes, start_idx..) |*node, i| {
        try steps.append(gpa, .{ .id = step, .step = .{ .change_state = .{ .index = i, .from = node.state, .to = to } } });
        // This is bad, this should be somewhere else
        node.state = to;
    }
}
