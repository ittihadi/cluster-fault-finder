const std = @import("std");
const builtin = @import("builtin");

const rg = @import("raygui");
const rl = @import("raylib");

const solver = @import("solver.zig");
const NodeCollection = @import("NodeCollection.zig");

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

var drag_mode = false;
var press_position: rl.Vector2 = .zero();
var show_faulty = true;
var show_welcome_screen = true;
var setup_mode = true;

var last_spread_radius: f32 = 0;

var ui_bounds: std.array_hash_map.String(rl.Rectangle) = .empty;
var solve_steps: []solver.SolveStep = &.{};

pub fn main(init: std.process.Init) !void {
    var frame_arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer frame_arena.deinit();
    const frame_alloc = frame_arena.allocator();

    var prng: std.Random.DefaultPrng = .init(@intCast(std.Io.Timestamp.now(init.io, .real).toMilliseconds()));
    const rng = prng.random();

    _ = rng.int(u32);

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1280, 720, "Fake Coin Problem");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    rg.setStyle(.default, .{ .default = .text_size }, 20);

    camera.offset.x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
    camera.offset.y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;

    defer nodes.deinit(init.gpa);
    defer ui_bounds.deinit(init.gpa);
    defer init.gpa.free(solve_steps);

    // Add UI element locations
    try ui_bounds.put(init.gpa, "add_many", .init(10, 10, 120, 30));
    try ui_bounds.put(init.gpa, "show_faulty", .init(10, 50, 20, 20));
    try ui_bounds.put(init.gpa, "solve", .init(10, 80, 120, 30));
    try ui_bounds.put(init.gpa, "node_count", .init(10, 120, 200, 20));

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
            if (rl.isKeyReleased(.x)) {
                nodes.sortByX(0, nodes.count());
            }

            if (rl.isKeyReleased(.y)) {
                nodes.sortByY(0, nodes.count());
            }

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
                nodes.setFaulty(selected_idx.?);
            }

            // Delete Nodes
            if (selected_idx != null and rl.isMouseButtonReleased(.right)) {
                nodes.remove(selected_idx.?);
                selected_idx = null;
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

                if (selected_idx != null and selected_idx.? == i) {
                    rl.drawTexturePro(texture, texture_frames.hover, dest_rect, texture_orig, camera.rotation, colors.hover);
                }

                // Show faulty node
                if (node.faulty and show_faulty) {
                    rl.drawTexturePro(texture, texture_frames.highlight, dest_rect, texture_orig, camera.rotation, colors.faulty);
                }
            }

            // Debug text, put here to batch drawing properly
            if (builtin.mode == .Debug) {
                for (nodes.array_list.items, 0..) |node, i| {
                    const dest_rect: rl.Rectangle = .init(node.x, node.y, 32, 32);
                    const idx_text = try std.fmt.allocPrintSentinel(frame_alloc, "{d}", .{i}, 0);
                    rl.drawText(idx_text, @trunc(dest_rect.x - 16), @trunc(dest_rect.y - 26), @trunc(10 / camera.zoom), .magenta);
                }
            }

            camera.end();
        }

        if (rg.button(ui_bounds.get("add_many").?, "Add 50")) {
            const to_place = 50;
            var placed: u32 = 0;
            var radius: f32 = last_spread_radius - 8;
            while (placed < to_place) {
                radius += 8;
                const it_max = to_place - placed;
                for (0..it_max) |_| {
                    const rand_x: f32 = @floatFromInt(rng.intRangeAtMost(
                        i32,
                        @trunc(camera.target.x - radius),
                        @trunc(camera.target.x + radius),
                    ));
                    const rand_y: f32 = @floatFromInt(rng.intRangeAtMost(
                        i32,
                        @trunc(camera.target.y - radius),
                        @trunc(camera.target.y + radius),
                    ));
                    if (nodes.findAtPos(rand_x, rand_y, 32)) |_| {
                        continue;
                    } else {
                        placed += 1;
                        try nodes.append(init.gpa, .init(rand_x, rand_y));
                    }
                }
            }
            // last_spread_radius = @max(last_spread_radius, radius);
            nodes.sortByX(0, nodes.count());
        }

        _ = rg.checkBox(ui_bounds.get("show_faulty").?, "Show Faulty Node", &show_faulty);

        if (rg.button(ui_bounds.get("solve").?, "Find Faulty")) {
            init.gpa.free(solve_steps);
            nodes.sortByX(0, nodes.count());
            solve_steps = try solver.solve(&nodes, init.gpa, 0, nodes.count(), 0);

            for (solve_steps) |step| {
                switch (step.step) {
                    .change_state => |state_change| {
                        std.debug.print(
                            "Step: {d}, change node {d} state from {s} to {s}\n",
                            .{ step.id, state_change.index, @tagName(state_change.from), @tagName(state_change.to) },
                        );
                    },
                    .found_at_index => |idx| std.debug.print("Step: {d} found faulty node at: {d}\n", .{ step.id, idx }),
                    else => {},
                }
            }
        }

        const node_count_text = try std.fmt.allocPrintSentinel(frame_alloc, "Node count: {d}", .{nodes.count()}, 0);
        _ = rg.label(ui_bounds.get("node_count").?, node_count_text);

        _ = frame_arena.reset(.retain_capacity);
    }
}
