const std = @import("std");

const rg = @import("raygui");
const rl = @import("raylib");

const solver = @import("solver.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    _ = arena;

    const screen_width = 640;
    const screen_height = 480;

    rl.initWindow(screen_width, screen_height, "Fake Coin Problem");
    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);
        rl.drawText("Hello", 100, 100, 20, .black);
    }
}
