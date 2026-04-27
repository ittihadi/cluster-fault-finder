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
    pub const suspect_a: rl.Color = .init(0xea, 0xf3, 0x12, 0xff);
    pub const suspect_b: rl.Color = .init(0xf3, 0xaf, 0x12, 0xff);
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
var show_help_screen = false;
var setup_mode = true;

var ui_bounds: std.array_hash_map.String(rl.Rectangle) = .empty;
var solve_steps: []solver.SolveStep = &.{};

const visualizer = struct {
    pub var playing = false;
    pub var current_frame: u32 = 0;
    pub var next_step: u32 = 0;
    /// Maps which frame a single step (single instance in a group) happens
    pub var step_frame_mapping: []u32 = &.{};
    pub var current_checks: u32 = 0;
};

pub fn main(init: std.process.Init) !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1280, 720, "Cluster Fault Finder Simulator");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    rg.setStyle(.default, .{ .default = .text_size }, 20);
    rg.setIconScale(2);

    camera.offset.x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
    camera.offset.y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;

    var frame_arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer frame_arena.deinit();
    const frame_alloc = frame_arena.allocator();

    var prng: std.Random.DefaultPrng = .init(@intCast(std.Io.Timestamp.now(init.io, .real).toMilliseconds()));
    const rng = prng.random();

    defer nodes.deinit(init.gpa);
    defer ui_bounds.deinit(init.gpa);
    defer init.gpa.free(solve_steps);
    defer init.gpa.free(visualizer.step_frame_mapping);

    // Add UI element locations
    try ui_bounds.put(init.gpa, "setup_add_many", .init(10, 10, 120, 30));
    try ui_bounds.put(init.gpa, "setup_show_faulty", .init(140, 15, 20, 20));
    try ui_bounds.put(init.gpa, "setup_solve", .init(10, 50, 120, 30));
    try ui_bounds.put(init.gpa, "setup_solve_slow", .init(10, 90, 250, 30));
    try ui_bounds.put(init.gpa, "setup_node_count", .init(140, 55, 200, 20));
    try ui_bounds.put(init.gpa, "setup_cant_solve", .init(10, 130, 330, 60));

    try ui_bounds.put(init.gpa, "sim_exit", .init(10, 10, 30, 30));
    try ui_bounds.put(init.gpa, "sim_back", .init(50, 10, 30, 30));
    try ui_bounds.put(init.gpa, "sim_play_pause", .init(90, 10, 30, 30));
    try ui_bounds.put(init.gpa, "sim_forward", .init(130, 10, 30, 30));
    try ui_bounds.put(init.gpa, "sim_node_count", .init(10, 50, 240, 20));
    try ui_bounds.put(init.gpa, "sim_check", .init(10, 80, 240, 20));
    try ui_bounds.put(init.gpa, "sim_frame", .init(10, 110, 240, 20));

    try ui_bounds.put(init.gpa, "info", .init(@floatFromInt(rl.getScreenWidth() - 40), 10, 30, 30));

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

            try ui_bounds.put(init.gpa, "info", .init(@floatFromInt(rl.getScreenWidth() - 40), 10, 30, 30));
        }

        var hovering_ui = false;
        for (ui_bounds.keys(), ui_bounds.values()) |key, bound| {
            if ((setup_mode and std.mem.startsWith(u8, key, "sim")) or
                (!setup_mode and std.mem.startsWith(u8, key, "setup")))
            {
                continue;
            }

            if (rl.checkCollisionPointRec(rl.getMousePosition(), bound)) {
                hovering_ui = true;
                break;
            }
        }

        if (show_welcome_screen) {
            if (rl.isKeyPressed(.space) or rl.isMouseButtonPressed(.left) or
                rl.isMouseButtonPressed(.middle) or rl.isMouseButtonPressed(.right))
            {
                show_welcome_screen = false;
            }
        } else if (show_help_screen) {
            if ((rl.isKeyPressed(.space) or rl.isMouseButtonPressed(.left) or
                rl.isMouseButtonPressed(.middle) or rl.isMouseButtonPressed(.right)) and
                !rl.checkCollisionPointRec(rl.getMousePosition(), ui_bounds.get("info").?))
            {
                show_help_screen = false;
            }
        } else if (!hovering_ui) {
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

            if (setup_mode) {
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
                    std.debug.print("Set node {d} as faulty\n", .{selected_idx.?});
                }

                // Delete Nodes
                if (selected_idx != null and rl.isMouseButtonReleased(.right)) {
                    nodes.remove(selected_idx.?);
                    selected_idx = null;
                }
            }
        }

        // Update visualizer
        if (!setup_mode) blk: {
            if (solve_steps.len == 0) {
                break :blk;
            }

            if (visualizer.playing and !show_help_screen) {
                visualizer.current_frame += 1;

                var frame_bound = visualizer.step_frame_mapping[visualizer.next_step];
                while (frame_bound <= visualizer.current_frame) {
                    applyStep(visualizer.next_step);
                    switch (solve_steps[visualizer.next_step].step) {
                        .found_at_index => {
                            visualizer.playing = false;
                            break;
                        },
                        else => {
                            visualizer.next_step += 1;
                            frame_bound = visualizer.step_frame_mapping[visualizer.next_step];
                        },
                    }
                }
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
                if (setup_mode) {
                    rl.drawTexturePro(texture, texture_frames.base, dest_rect, texture_orig, camera.rotation, .white);

                    if (selected_idx != null and selected_idx.? == i) {
                        rl.drawTexturePro(texture, texture_frames.hover, dest_rect, texture_orig, camera.rotation, colors.hover);
                    }

                    // Show faulty node
                    if (node.faulty and show_faulty and setup_mode) {
                        rl.drawTexturePro(texture, texture_frames.highlight, dest_rect, texture_orig, camera.rotation, colors.faulty);
                    }
                }
                // Show state
                else {
                    rl.drawTexturePro(
                        texture,
                        texture_frames.base,
                        dest_rect,
                        texture_orig,
                        camera.rotation,
                        switch (node.state) {
                            .safe => rl.Color.init(0xbb, 0xbb, 0xbb, 0xff),
                            else => rl.Color.white,
                        },
                    );

                    if (node.state != .neutral) {
                        rl.drawTexturePro(
                            texture,
                            texture_frames.highlight,
                            dest_rect,
                            texture_orig,
                            camera.rotation,
                            switch (node.state) {
                                .counterfeit => colors.faulty,
                                .safe => colors.safe,
                                .suspect_a => colors.suspect_a,
                                .suspect_b => colors.suspect_b,
                                else => unreachable,
                            },
                        );
                    }
                }
            }

            // Preview placement
            if (selected_idx == null and !hovering_ui and setup_mode and !show_help_screen and !show_welcome_screen) {
                const dest_rect: rl.Rectangle = .init(mouse_pos_world.x, mouse_pos_world.y, 32, 32);
                rl.drawTexturePro(texture, texture_frames.base, dest_rect, texture_orig, camera.rotation, .init(0xff, 0xff, 0xff, 0x55));
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

        // Draw UI

        // Setup UI
        // "I don't want big diffs which is why I didn't just indent another level lol"
        if (setup_mode and !show_welcome_screen and !show_help_screen) {
            if (rg.button(ui_bounds.get("setup_add_many").?, "Add 50")) {
                const to_place = 50;
                var placed: u32 = 0;
                var radius: f32 = 0;
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
                nodes.sortByX(0, nodes.count());
            }

            _ = rg.checkBox(ui_bounds.get("setup_show_faulty").?, "Show Faulty Node", &show_faulty);

            const can_solve = nodes.count() > 1 and hasFaultyNode();

            if (!can_solve) {
                const prev = rg.getStyle(.default, .{ .control = .text_color_normal });
                rg.setStyle(.default, .{ .control = .text_color_normal }, colors.faulty.toInt());
                _ = rg.label(ui_bounds.get("setup_cant_solve").?, "Ensure at least two nodes exist\nand that one is marked faulty");
                rg.setStyle(.default, .{ .control = .text_color_normal }, prev);
                rg.disable();
            }

            if (rg.button(ui_bounds.get("setup_solve").?, "Find Faulty")) {
                init.gpa.free(solve_steps);
                nodes.sortByX(0, nodes.count());
                solve_steps = try solver.solve(&nodes, init.gpa, 0, nodes.count(), 0);

                if (builtin.mode == .Debug) {
                    for (solve_steps) |step| {
                        switch (step.step) {
                            .change_state => |state_change| {
                                std.debug.print(
                                    "Step: {d}, change node {d} state from {s} to {s}\n",
                                    .{ step.id, state_change.index, @tagName(state_change.from), @tagName(state_change.to) },
                                );
                            },
                            .found_at_index => |idx| {
                                std.debug.print("Step: {d}, found faulty node at: {d}\n", .{ step.id, idx });
                            },
                            .compare_size => |size| {
                                std.debug.print("Step: {d}, current comparison size: {d}\n", .{ step.id, size });
                            },
                            .start_compare => {
                                std.debug.print("Step: {d}, start comparison\n", .{step.id});
                            },
                            else => unreachable,
                        }
                    }
                }

                try setupVisualizer(init.gpa, rng);
                setup_mode = false;
            }

            if (rg.button(ui_bounds.get("setup_solve_slow").?, "Find Faulty Brute Force")) {
                init.gpa.free(solve_steps);
                nodes.sortByX(0, nodes.count());
                solve_steps = try solver.solveSlow(&nodes, init.gpa, 0, nodes.count(), 0);

                if (builtin.mode == .Debug) {
                    for (solve_steps) |step| {
                        switch (step.step) {
                            .change_state => |state_change| {
                                std.debug.print(
                                    "Step: {d}, change node {d} state from {s} to {s}\n",
                                    .{ step.id, state_change.index, @tagName(state_change.from), @tagName(state_change.to) },
                                );
                            },
                            .found_at_index => |idx| {
                                std.debug.print("Step: {d}, found faulty node at: {d}\n", .{ step.id, idx });
                            },
                            .compare_size => |size| {
                                std.debug.print("Step: {d}, current comparison size: {d}\n", .{ step.id, size });
                            },
                            .start_compare => {
                                std.debug.print("Step: {d}, start comparison\n", .{step.id});
                            },
                            else => unreachable,
                        }
                    }
                }

                try setupVisualizer(init.gpa, rng);
                setup_mode = false;
            }

            if (!can_solve) {
                rg.enable();
            }

            const node_count_text = try std.fmt.allocPrintSentinel(frame_alloc, "Node count: {d}", .{nodes.count()}, 0);
            _ = rg.label(ui_bounds.get("setup_node_count").?, node_count_text);
        }
        // Simulation/Visualization UI
        else if (!setup_mode and !show_welcome_screen and !show_help_screen) {
            const sim_exit = ui_bounds.get("sim_exit").?;
            if (rg.button(sim_exit, rg.iconText(@intFromEnum(rg.IconName.cross), ""))) {
                visualizer.playing = false;
                setup_mode = true;
            }

            const sim_back = ui_bounds.get("sim_back").?;
            if (rg.button(sim_back, rg.iconText(@intFromEnum(rg.IconName.player_previous), ""))) {
                visualizer.playing = false;

                // So scuffed...
                const initial_id = solve_steps[visualizer.next_step].id;
                while (visualizer.next_step > 0) {
                    unapplyStep(visualizer.next_step);
                    visualizer.next_step -= 1;
                    visualizer.current_frame = visualizer.step_frame_mapping[visualizer.next_step];
                    const curr_step = solve_steps[visualizer.next_step];
                    if (curr_step.id != initial_id) {
                        // This has to happen *after* the shift otherwise there's an edge case where
                        // it gains one
                        if (curr_step.step == .start_compare) {
                            visualizer.current_checks -= 1;
                        }
                        break;
                    }
                }
                if (visualizer.next_step == 0) {
                    visualizer.current_frame = 0;
                }
            }

            const sim_toggle = ui_bounds.get("sim_play_pause").?;
            const icon = if (visualizer.playing) @intFromEnum(rg.IconName.player_pause) else @intFromEnum(rg.IconName.player_play);
            if (rg.button(sim_toggle, rg.iconText(icon, ""))) {
                visualizer.playing = !visualizer.playing;
            }

            const sim_forward = ui_bounds.get("sim_forward").?;
            if (rg.button(sim_forward, rg.iconText(@intFromEnum(rg.IconName.player_next), ""))) {
                visualizer.playing = false;

                // Not as scuffed
                const initial_id = solve_steps[visualizer.next_step].id;
                var curr_step = solve_steps[visualizer.next_step];
                while (curr_step.id == initial_id) {
                    applyStep(visualizer.next_step);
                    visualizer.current_frame = visualizer.step_frame_mapping[visualizer.next_step];
                    switch (curr_step.step) {
                        .found_at_index => break,
                        else => visualizer.next_step += 1,
                    }
                    curr_step = solve_steps[visualizer.next_step];
                }
            }

            const sim_node_count = ui_bounds.get("sim_node_count").?;
            const node_count_text = try std.fmt.allocPrintSentinel(frame_alloc, "Node count: {d}", .{nodes.count()}, 0);
            _ = rg.label(sim_node_count, node_count_text);

            const sim_check = ui_bounds.get("sim_check").?;
            const node_check_text = try std.fmt.allocPrintSentinel(frame_alloc, "Current Checks: {d}", .{visualizer.current_checks}, 0);
            _ = rg.label(sim_check, node_check_text);

            const sim_frame = ui_bounds.get("sim_frame").?;
            const node_frame_text = try std.fmt.allocPrintSentinel(frame_alloc, "Current Frame: {d}", .{visualizer.current_frame}, 0);
            _ = rg.label(sim_frame, node_frame_text);
        }

        if (show_help_screen) {
            const center_x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
            const center_y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
            const panel_bounds: rl.Rectangle = if (setup_mode)
                .init(center_x - 250, center_y - 120, 500, 240)
            else
                .init(center_x - 250, center_y - 180, 500, 360);
            const panel_color = rg.getStyle(.default, .{ .default = .background_color });
            const text_color: rl.Color = .fromInt(@bitCast(rg.getStyle(.default, .{ .control = .text_color_normal })));

            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), .init(0x88, 0x88, 0x88, 0x44));
            rl.drawRectangleRounded(panel_bounds, 0.05, 10, .fromInt(@bitCast(panel_color)));

            const title_text: [:0]const u8 = "Help";
            const title_w: f32 = @floatFromInt(rl.measureText(title_text, 20));
            rl.drawText(title_text, @trunc(center_x - title_w / 2), @trunc(panel_bounds.y + 16), 20, text_color);

            const inst_txt: [:0]const u8 = if (setup_mode)
                \\- Place nodes by Left clicking
                \\- Remove nodes by Right clicking
                \\- Move by holding Middle Mouse click or
                \\  Space and dragging the screen
                \\- Zoom using the scroll wheel
                \\- Left click a node to mark it as faulty
            else
                \\- Use the Close button to go back to setup
                \\  mode
                \\- Use the Back, Pause/Play, and Forward
                \\  buttons to navigate around the simulation
                \\- Move by holding Middle Mouse Button or
                \\  Space and dragging the screen
                \\- Zoom using the scroll wheel
                \\Nodes are outlined the following way:
                \\- Orange / Yellow - Groups being compared
                \\- Red - Found faulty node
                \\- Green - Known safe node
                \\- No outline - Not currently considered
            ;
            rl.drawText(inst_txt, @trunc(panel_bounds.x + 16), @trunc(panel_bounds.y + 52), 20, text_color);

            const author_txt: [:0]const u8 = "Application by Ittihadi Ramadhan (24343038)";
            const author_w: f32 = @floatFromInt(rl.measureText(author_txt, 10));
            const author_y: i32 = @trunc(panel_bounds.y + panel_bounds.height - 16 - 10);
            rl.drawText(author_txt, @trunc(center_x - author_w / 2), author_y, 10, text_color);
        }

        if (show_welcome_screen) {
            // Draw welcome screen
            const center_x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2;
            const center_y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2;
            const panel_bounds: rl.Rectangle = .init(center_x - 250, center_y - 100, 500, 200);
            const panel_color = rg.getStyle(.default, .{ .default = .background_color });
            const text_color: rl.Color = .fromInt(@bitCast(rg.getStyle(.default, .{ .control = .text_color_normal })));

            rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), .init(0x88, 0x88, 0x88, 0x44));
            rl.drawRectangleRounded(panel_bounds, 0.05, 10, rl.colorAlpha(.fromInt(@bitCast(panel_color)), 0.7));

            const title_text: [:0]const u8 = "Cluster Computer Fault Tracker Simulator";
            const title_w: f32 = @floatFromInt(rl.measureText(title_text, 20));
            rl.drawText(title_text, @trunc(center_x - title_w / 2), @trunc(panel_bounds.y + 16), 20, text_color);

            const inst_txt: [:0]const u8 =
                \\- Setup a cluster nodes with left click
                \\- Simulate a node being faulty
                \\- Press the Find Faulty button to find the
                \\  faulty node with decrease and conquer
            ;
            rl.drawText(inst_txt, @trunc(panel_bounds.x + 16), @trunc(panel_bounds.y + 52), 20, text_color);

            const anywhere_txt: [:0]const u8 = "Click anywhere to start";
            const anywhere_w: f32 = @floatFromInt(rl.measureText(anywhere_txt, 10));
            const anywhere_y: i32 = @trunc(panel_bounds.y + panel_bounds.height - 16 - 10);
            rl.drawText(anywhere_txt, @trunc(center_x - anywhere_w / 2), anywhere_y, 10, text_color);
        } else {
            if (rg.button(ui_bounds.get("info").?, rg.iconText(@intFromEnum(rg.IconName.help), ""))) {
                show_help_screen = !show_help_screen;
            }
        }

        _ = frame_arena.reset(.retain_capacity);
    }
}

fn hasFaultyNode() bool {
    for (nodes.array_list.items) |item| {
        if (item.faulty) {
            return true;
        }
    }
    return false;
}

fn setupVisualizer(gpa: std.mem.Allocator, rng: std.Random) !void {
    visualizer.playing = false;
    visualizer.next_step = 0;
    visualizer.current_frame = 0;
    visualizer.current_checks = 0;

    gpa.free(visualizer.step_frame_mapping);
    visualizer.step_frame_mapping = try gpa.alloc(u32, solve_steps.len);

    // Reset all states
    for (nodes.array_list.items) |*node| {
        node.state = .neutral;
    }

    // Setup step -> frame mapping
    const startup_padding: u32 = 30;
    var current_frame = startup_padding;
    var current_step: usize = 0;
    var current_comparison_size: usize = 0;
    const fast_comparison_thresh = 30;
    const really_fast_comparison_thresh = 60;
    var sub_frame_counter: u32 = 0;

    while (current_step < solve_steps.len) : (current_step += 1) {
        const curr = solve_steps[current_step];
        const next = if (current_step < solve_steps.len - 1) solve_steps[current_step + 1] else curr;
        visualizer.step_frame_mapping[current_step] = current_frame;
        switch (curr.step) {
            .start_compare => {
                current_frame += rng.intRangeAtMost(u32, 120, 180);
            },
            .compare_size => |size| {
                current_comparison_size = size;
            },
            .change_state => |change| {
                switch (change.to) {
                    .safe, .neutral, .counterfeit => {
                        if (current_comparison_size < 10) {
                            current_frame += 1;
                        } else {
                            sub_frame_counter += 1;
                            if (sub_frame_counter >= 10) {
                                sub_frame_counter = 0;
                                current_frame += 1;
                            }
                        }

                        if (next.id > curr.id) {
                            current_frame += 20;
                        }
                    },
                    .suspect_a, .suspect_b => {
                        if (current_comparison_size >= really_fast_comparison_thresh) {
                            sub_frame_counter += 1;
                            if (sub_frame_counter >= 20) {
                                sub_frame_counter = 0;
                                current_frame += 1;
                            }
                        } else if (current_comparison_size >= fast_comparison_thresh) {
                            current_frame += 1;
                        } else {
                            current_frame += 6;
                        }
                    },
                }
            },
            .found_at_index => {},
            .incorrect_input => unreachable,
        }

        if (curr.id != next.id) {
            sub_frame_counter = 0;
        }
    }
}

fn applyStep(step: usize) void {
    switch (solve_steps[step].step) {
        .compare_size, .found_at_index => {},
        .start_compare => visualizer.current_checks += 1,
        .change_state => |change| {
            nodes.array_list.items[change.index].state = change.to;
            // std.debug.print("Changed state of {d} from {s} to {s}\n", .{ change.index, @tagName(change.from), @tagName(change.to) });
        },
        .incorrect_input => unreachable,
    }
}

fn unapplyStep(step: usize) void {
    switch (solve_steps[step].step) {
        .compare_size, .found_at_index => {},
        .start_compare => {},
        .change_state => |change| {
            nodes.array_list.items[change.index].state = change.from;
        },
        .incorrect_input => unreachable,
    }
}
