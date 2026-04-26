const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const solver = @import("solver.zig");

// Constants
const f32_eps = std.math.floatEps(f32);
const press_thresh = 32;

const server_tex_file = @embedFile("server.png");
const floor_tex_file = @embedFile("floor.png");
const texture_orig: rl.Vector2 = .init(16, 16);
const texture_frames = struct {
    pub const base: rl.Rectangle = .init(0, 0, 32, 32);
    pub const hover: rl.Rectangle = .init(0, 32, 32, 32);
    pub const highlight: rl.Rectangle = .init(0, 64, 32, 32);
};

const colors = struct {
    pub const hover: rl.Color = .init(0xff, 0xff, 0xff, 0xff);
    pub const safe: rl.Color = .init(0x3e, 0xfb, 0x3e, 0xff);
    pub const suspect_1: rl.Color = .init(0xea, 0xf3, 0x12, 0xff);
    pub const suspect_2: rl.Color = .init(0xf3, 0xaf, 0x12, 0xff);
    pub const faulty: rl.Color = .init(0xf3, 0x2e, 0x2e, 0xff);
};

// Variables
var texture: rl.Texture2D = undefined;
var floor: rl.Texture2D = undefined;
var camera: rl.Camera2D = .{ .offset = .zero(), .rotation = 0, .target = .zero(), .zoom = 2 };
var nodes: NodeCollection = .empty;

var drag_mode: bool = false;
var press_position: rl.Vector2 = .zero();

var ui_bounds: std.array_hash_map.String(rl.Rectangle) = .empty;

// Types
const NodeCollection = struct {
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

    fn lessThanX(ctx: void, a: solver.Node, b: solver.Node) bool {
        _ = ctx;
        return a.x < b.x;
    }

    fn lessThanY(ctx: void, a: solver.Node, b: solver.Node) bool {
        _ = ctx;
        return a.y < b.y;
    }

    // Items sorted by increasing x position
    pub fn sortByX(self: *NodeCollection) void {
        std.sort.heap(solver.Node, self.array_list.items, {}, lessThanX);
    }
    // Items sorted by increasing y position
    pub fn sortByY(self: *NodeCollection) void {
        std.sort.heap(solver.Node, self.array_list.items, {}, lessThanY);
    }

    pub fn setFaulty(self: *NodeCollection, idx: usize) void {
        _ = self;
        _ = idx;
        //
    }
};

pub fn main(init: std.process.Init) !void {
    var frame_arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer frame_arena.deinit();
    const frame_alloc = frame_arena.allocator();

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1280, 720, "Fake Coin Problem");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    camera.offset.x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
    camera.offset.y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;

    defer nodes.deinit(init.gpa);
    defer ui_bounds.deinit(init.gpa);

    try ui_bounds.put(init.gpa, "add_100", .init(10, 10, 120, 30));

    texture = blk: {
        const img = try rl.loadImageFromMemory(".png", server_tex_file);
        rl.unloadImage(img);
        break :blk try rl.loadTextureFromImage(img);
    };
    defer rl.unloadTexture(texture);

    floor = blk: {
        const img = try rl.loadImageFromMemory(".png", floor_tex_file);
        rl.unloadImage(img);
        break :blk try rl.loadTextureFromImage(img);
    };
    defer rl.unloadTexture(floor);

    while (!rl.windowShouldClose()) {
        // Update
        const mouse_pos_world = rl.getScreenToWorld2D(rl.getMousePosition(), camera);
        const scroll_delta = rl.getMouseWheelMoveV().y;

        var selected_idx: ?usize = null;

        // Re-center camera on resize
        if (rl.isWindowResized()) {
            @branchHint(.unlikely);
            camera.offset.x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
            camera.offset.y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
        }

        var hovering_ui = false;
        for (ui_bounds.values()) |bound| {
            if (rl.checkCollisionPointRec(rl.getMousePosition(), bound)) {
                hovering_ui = true;
                break;
            }
        }

        if (!hovering_ui) {

            // Check for camera drag
            if (rl.isKeyPressed(.space) or rl.isMouseButtonPressed(.middle)) {
                drag_mode = true;
                rl.setMouseCursor(.resize_all);
            } else if (rl.isKeyReleased(.space) or rl.isMouseButtonReleased(.middle)) {
                drag_mode = false;
                rl.setMouseCursor(.default);
            }

            // Move camera
            if (drag_mode) {
                const mouse_delta = rl.getMouseDelta();
                const new_target = camera.target.add(mouse_delta.scale(-1 / camera.zoom));
                camera.target = new_target;
            }

            // Zoom
            if (!std.math.approxEqAbs(f32, scroll_delta, 0, f32_eps)) {
                camera.zoom = std.math.clamp(camera.zoom + (scroll_delta / 10 * camera.zoom), 0.2, 5);
            }

            if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right)) {
                press_position = mouse_pos_world;
            }

            // Get current node
            selected_idx = nodes.findAtPos(mouse_pos_world.x, mouse_pos_world.y, 24);

            // Place Nodes
            if (selected_idx == null and rl.isMouseButtonReleased(.left) and
                press_position.distanceSqr(mouse_pos_world) < press_thresh * press_thresh)
            {
                try nodes.append(init.gpa, .init(mouse_pos_world.x, mouse_pos_world.y));
            }

            // Mark Node
            if (selected_idx != null and rl.isMouseButtonReleased(.left)) {
                //
            }

            // Delete Nodes
            if (selected_idx != null and rl.isMouseButtonReleased(.right)) {
                nodes.remove(selected_idx.?);
            }

            if (rl.isKeyReleased(.x)) {
                nodes.sortByX();
            }

            if (rl.isKeyReleased(.y)) {
                nodes.sortByY();
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        { // Camera Drawing
            camera.begin();

            // Draw Floor
            {
                const half_w = @as(f32, @floatFromInt(rl.getScreenWidth())) / camera.zoom / 2;
                const half_h = @as(f32, @floatFromInt(rl.getScreenHeight())) / camera.zoom / 2;

                const tex_w: f32 = @floatFromInt(floor.width);
                const tex_h: f32 = @floatFromInt(floor.height);

                const lo_x = camera.target.x - half_w - @mod(camera.target.x - half_w, tex_w);
                const lo_y = camera.target.y - half_h - @mod(camera.target.y - half_h, tex_h);

                var x = lo_x;
                while (x <= camera.target.x + half_w) : (x += tex_w) {
                    var y = lo_y;
                    while (y <= camera.target.y + half_h) : (y += tex_h) {
                        rl.drawTexture(floor, @trunc(x), @trunc(y), .white);
                    }
                }
            }

            // Draw all nodes
            for (nodes.array_list.items, 0..) |node, i| {
                const dest_rect: rl.Rectangle = .init(node.x, node.y, 32, 32);
                rl.drawTexturePro(texture, texture_frames.base, dest_rect, texture_orig, camera.rotation, .white);

                const idx_text = try std.fmt.allocPrintSentinel(frame_alloc, "{d}", .{i}, 0);
                rl.drawText(idx_text, @trunc(dest_rect.x - 16), @trunc(dest_rect.y - 26), 10, .gray);

                if (selected_idx != null and selected_idx.? == i) {
                    rl.drawTexturePro(texture, texture_frames.hover, dest_rect, texture_orig, camera.rotation, colors.hover);
                }
            }

            camera.end();
        }

        const mouse_pos_text = try std.fmt.allocPrintSentinel(
            frame_alloc,
            "Mouse pos: {d:.2}, {d:.2}",
            .{ mouse_pos_world.x, mouse_pos_world.y },
            0,
        );

        rl.drawText(mouse_pos_text, 100, 120, 10, .gray);

        if (rg.button(ui_bounds.get("add_100").?, "Add 100")) {
            //
        }

        _ = frame_arena.reset(.retain_capacity);
    }
}
