const std = @import("std");
const solver = @import("solver.zig");
const rl = @import("raylib");
const NodeCollection = @This();

const f32_eps = std.math.floatEps(f32);

array_list: std.ArrayList(solver.Node),

pub const empty: NodeCollection = .{
    .array_list = .empty,
};

pub fn deinit(self: *NodeCollection, gpa: std.mem.Allocator) void {
    self.array_list.deinit(gpa);
}

pub fn append(self: *NodeCollection, gpa: std.mem.Allocator, item: solver.Node) error{OutOfMemory}!void {
    return self.array_list.append(gpa, item);
}

// Find at position
pub fn findAtPos(self: *const NodeCollection, x: f32, y: f32, r: f32) ?usize {
    var best_dist: f32 = std.math.inf(f32);
    var best_idx: ?usize = null;

    const v1: rl.Vector2 = .init(x, y);
    for (self.array_list.items, 0..) |node, i| {
        const v2: rl.Vector2 = .init(node.x, node.y);
        const dist = v1.distanceSqr(v2);
        if (dist < r * r and dist < best_dist) {
            best_dist = dist;
            best_idx = i;
        }
    }
    return best_idx orelse null;
}

// Remove item
pub fn remove(self: *NodeCollection, idx: usize) void {
    _ = self.array_list.swapRemove(idx);
}

fn lessThanX(_: void, a: solver.Node, b: solver.Node) bool {
    return if (std.math.approxEqAbs(f32, a.x, b.x, f32_eps)) a.y < b.y else a.x < b.x;
}

fn lessThanY(_: void, a: solver.Node, b: solver.Node) bool {
    return if (std.math.approxEqAbs(f32, a.y, b.y, f32_eps)) a.x < b.x else a.y < b.y;
}

// Items sorted by increasing x position
/// Start is inclusive and end is exclusive
pub fn sortByX(self: *NodeCollection, start: usize, end: usize) void {
    std.sort.heap(solver.Node, self.array_list.items[start..end], {}, lessThanX);
}
// Items sorted by increasing y position
/// Start is inclusive and end is exclusive
pub fn sortByY(self: *NodeCollection, start: usize, end: usize) void {
    std.sort.heap(solver.Node, self.array_list.items[start..end], {}, lessThanY);
}

pub fn setFaulty(self: *NodeCollection, idx: usize) void {
    for (self.array_list.items) |*node| {
        node.faulty = false;
    }
    self.array_list.items[idx].faulty = true;
}

pub fn count(self: *const NodeCollection) usize {
    return self.array_list.items.len;
}
