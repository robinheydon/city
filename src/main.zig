///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const glfw = @import("zglfw");
const gui = @import("zgui");
const opengl = @import("zopengl");
const gl = opengl.bindings;
const math = @import("zmath");
const tracy = @import("ztracy");
const stbi = @import("zstbi");

const fonts = @import("fonts.zig");
const gfx = @import("gfx.zig");
const random = @import("random.zig");
const terrain = @import("terrain.zig");
const rand = random.rand;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const TerrainMesh = gfx.Mesh(gfx.TerrainVertex);
const Mesh = gfx.Mesh(gfx.Vertex);

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const max_map_x = 64 * 1024;
pub const max_map_y = 64 * 1024;

const default_map_x = 32 * 1024;
const default_map_y = 32 * 1024;
const default_camera_yaw = 0;
const default_camera_pitch = 30;
const default_camera_zoom = 1000;

pub const State = struct {
    main_window: *glfw.Window = undefined,
    allocator: std.mem.Allocator = undefined,

    running: bool = true,

    show_debug: bool = false,
    show_fps: bool = true,
    show_terrain: bool = true,
    show_axes: bool = false,
    show_wireframe: bool = false,

    gui_capture_mouse: bool = false,
    gui_capture_keyboard: bool = false,
    gui_capture_text: bool = false,

    frame_times: [8]i64 = undefined,
    frame_time_index: usize = 0,
    frame_times_full: bool = true,
    fps: f32 = 60.0,
    last_now: i64 = 0,
    now: f64 = 0,
    delta_time: f32 = 0,

    target_velocity: f32 = 0,
    yaw_velocity: f32 = 0,
    pitch_velocity: f32 = 0,
    zoom_velocity: f32 = 0,

    target_x: f32 = default_map_x,
    target_y: f32 = default_map_y,
    camera_yaw: f32 = default_camera_yaw,
    camera_pitch: f32 = default_camera_pitch,
    camera_zoom: f32 = default_camera_zoom,

    isaac64: std.rand.Isaac64 = undefined, // rand.zig
    random: std.rand.Random = undefined,

    width: i32 = undefined,
    height: i32 = undefined,

    height_map: [max_map_y / terrain.cell_size + 1][max_map_x / terrain.cell_size + 1]f32 = undefined,
    flat_map: [max_map_y / terrain.cell_size + 1][max_map_x / terrain.cell_size + 1]u8 = undefined,

    terrain_generation_requested: bool = false,
    terrain_generation_ready: bool = false,

    terrain_thread: std.Thread = undefined,

    target_terrain_tris: f32 = terrain.max_tris,
    terrain_detail: f32 = 1,
    terrain_frame_index: u1 = 0,
    terrain_mesh: [2]?TerrainMesh = .{ null, null },

    sun_angle: f32 = 45,
    sun_direction: f32 = 0,

    show_contour: f32 = 0.1,
    show_grid: f32 = 0.1,

    user_terrain_detail: f32 = 1.0,
    user_demo_window: bool = true,

    axes: Mesh = undefined,

    basic_shader: gfx.Shader = undefined,
    terrain_shader: gfx.Shader = undefined,

    fade_to_color: [3]f32 = undefined,

    main_camera: gfx.Camera = .{},
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub var state: State = .{};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn main() !void {
    const main_zone = tracy.ZoneNC(@src(), "main", 0x00_80_80_80);
    defer main_zone.End();

    const main_start_zone = tracy.ZoneNC(@src(), "main_start", 0x00_80_80_80);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer std.debug.assert(gpa.deinit() == .ok);

    var tracy_allocator = tracy.TracyAllocator{ .child_allocator = gpa.allocator() };
    state.allocator = tracy_allocator.allocator();

    // std.debug.print("City\n", .{});
    // std.debug.print("  cpus = {}\n", .{try std.Thread.getCpuCount()});

    random.init();

    stbi.init(state.allocator);
    defer stbi.deinit();

    try terrain.init_height_map();

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 3;

    glfw.windowHintTyped(.context_version_major, gl_major);
    glfw.windowHintTyped(.context_version_minor, gl_minor);
    glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
    glfw.windowHintTyped(.opengl_forward_compat, true);
    glfw.windowHintTyped(.opengl_debug_context, true);
    glfw.windowHintTyped(.client_api, .opengl_api);
    glfw.windowHintTyped(.red_bits, 8);
    glfw.windowHintTyped(.green_bits, 8);
    glfw.windowHintTyped(.blue_bits, 8);
    glfw.windowHintTyped(.depth_bits, 24);
    glfw.windowHintTyped(.doublebuffer, true);
    glfw.windowHintTyped(.samples, 8);

    state.main_window = try glfw.Window.create(1280, 720, "City", null);
    defer state.main_window.destroy();

    glfw.makeContextCurrent(state.main_window);

    try opengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    gl.debugMessageCallback(opengl_debug_message, null);
    gl.enable(gl.DEBUG_OUTPUT);

    glfw.swapInterval(1);

    gl.clearColor(0.4, 0.4, 0.4, 1.0);
    gl.clearDepth(1.0);
    gl.clear(gl.DEPTH_BUFFER_BIT | gl.COLOR_BUFFER_BIT);
    state.main_window.swapBuffers();

    _ = state.main_window.setKeyCallback(on_key);
    _ = state.main_window.setCharCallback(on_char);
    _ = state.main_window.setCursorPosCallback(on_mouse_move);

    gui.init(state.allocator);
    defer gui.deinit();

    gui.backend.init(state.main_window);
    defer gui.backend.deinit();

    _ = gui.io.addFontFromMemory(fonts.atkinson_regular, 24);

    gui.getStyle().scaleAllSizes(2);

    state.target_x = default_map_x;
    state.target_y = default_map_y;
    state.camera_yaw = default_camera_yaw;
    state.camera_pitch = default_camera_pitch;
    state.camera_zoom = default_camera_zoom;

    try create_shaders();

    try create_axes();
    defer state.axes.deinit();

    gl.enable(gl.CULL_FACE);
    gl.cullFace(gl.BACK);
    gl.frontFace(gl.CW);
    gl.depthFunc(gl.LEQUAL);
    gl.enable(gl.DEPTH_TEST);

    state.fade_to_color[0] = 0.35;
    state.fade_to_color[1] = 0.35;
    state.fade_to_color[2] = 0.35;

    try terrain.init ();
    defer terrain.deinit ();

    main_start_zone.End();

    reset_delta_time();

    while (state.running) {
        tracy.FrameMark();

        if (state.main_window.shouldClose()) {
            state.running = false;
        }

        update_delta_time();

        {
            const zone = tracy.ZoneNC(@src(), "gl.viewport", 0x00_80_80_80);
            defer zone.End();

            const fb_size = state.main_window.getFramebufferSize();
            state.width = fb_size[0];
            state.height = fb_size[1];

            gl.viewport(0, 0, state.width, state.height);
        }

        {
            const zone = tracy.ZoneNC(@src(), "gl.clear", 0x00_80_80_80);
            defer zone.End();

            gl.clearColor(0.4, 0.4, 0.4, 1.0);
            gl.clearDepth(1.0);
            gl.clear(gl.DEPTH_BUFFER_BIT | gl.COLOR_BUFFER_BIT);
        }

        begin_3d();

        draw_axes();
        draw_terrain();

        draw_gui();
        draw_frame_times();

        {
            const zone = tracy.ZoneNC(@src(), "swapBuffers", 0x00_00_ff_00);
            defer zone.End();
            state.main_window.swapBuffers();
        }

        process_events();

        update_camera();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn reset_delta_time() void {
    state.last_now = std.time.microTimestamp();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn update_delta_time() void {
    const zone = tracy.ZoneNC(@src(), "update_delta_time", 0x00_ff_00_00);
    defer zone.End();

    const now = std.time.microTimestamp();
    const delta = now - state.last_now;
    state.last_now = now;

    state.now = @as(f64, @floatFromInt(now)) / std.time.us_per_s;

    state.delta_time = @as(f32, @floatFromInt(delta)) / std.time.us_per_s;

    state.frame_times[state.frame_time_index] = delta;
    state.frame_time_index += 1;
    if (state.frame_time_index == state.frame_times.len) {
        state.frame_time_index = 0;
        state.frame_times_full = true;
    }

    if (state.frame_times_full) {
        var total: i64 = 0;
        for (0..state.frame_times.len) |i| {
            total += state.frame_times[i];
        }
        const average: f32 = @as(f32, @floatFromInt(total)) / state.frame_times.len / std.time.us_per_s;
        state.fps = 1 / average;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn update_camera() void {
    const fast_multiplier: f32 = blk: {
        if (state.main_window.getKey(.left_shift) == .press) {
            break :blk 5;
        } else if (state.main_window.getKey(.left_control) == .press) {
            break :blk 0.2;
        } else {
            break :blk 1;
        }
    };

    if (!state.gui_capture_keyboard) {
        if (state.main_window.getKey(.t) == .press) {
            state.target_x = default_map_x;
            state.target_y = default_map_y;
            state.camera_yaw = default_camera_yaw;
            state.camera_pitch = default_camera_pitch;
            state.camera_zoom = default_camera_zoom;
        }
    }

    if (!state.gui_capture_keyboard) {
        var moving = false;

        if (state.main_window.getKey(.q) == .press) {
            state.camera_yaw += state.yaw_velocity * fast_multiplier * state.delta_time;
            moving = true;

            if (state.camera_yaw >= 360) {
                state.camera_yaw -= 360;
            }
        }

        if (state.main_window.getKey(.e) == .press) {
            state.camera_yaw -= state.yaw_velocity * fast_multiplier * state.delta_time;
            moving = true;

            if (state.camera_yaw < 0) {
                state.camera_yaw += 360;
            }
        }

        if (moving) {
            state.yaw_velocity = @min(90, state.yaw_velocity + 30 * state.delta_time);
        } else {
            state.yaw_velocity = 0;
        }
    }

    if (!state.gui_capture_keyboard) {
        var moving = false;

        if (state.main_window.getKey(.f) == .press) {
            state.camera_pitch = @max(15, state.camera_pitch - fast_multiplier * state.pitch_velocity * state.delta_time);
            moving = true;
        }

        if (state.main_window.getKey(.r) == .press) {
            state.camera_pitch = @min(75, state.camera_pitch + fast_multiplier * state.pitch_velocity * state.delta_time);
            moving = true;
        }

        if (moving) {
            state.pitch_velocity = @min(30, state.pitch_velocity + 10 * state.delta_time);
        } else {
            state.pitch_velocity = 0;
        }
    }

    if (!state.gui_capture_keyboard) {
        var moving = false;
        if (state.main_window.getKey(.z) == .press) {
            state.camera_zoom = @max(15, state.camera_zoom - fast_multiplier * state.zoom_velocity * state.delta_time);
            moving = true;
        }

        if (state.main_window.getKey(.x) == .press) {
            state.camera_zoom = @min(10000, state.camera_zoom + fast_multiplier * state.zoom_velocity * state.delta_time);
            moving = true;
        }

        if (moving) {
            state.zoom_velocity = @min(500, state.zoom_velocity + 100 * state.delta_time);
        } else {
            state.zoom_velocity = 0;
        }
    }

    const yaw = state.camera_yaw * std.math.pi / 180;
    const pitch = state.camera_pitch * std.math.pi / 180;

    const sy: f32 = @floatCast(@sin(yaw));
    const cy: f32 = @floatCast(@cos(yaw));

    const sp: f32 = @floatCast(@sin(pitch));
    const cp: f32 = @floatCast(@cos(pitch));

    if (!state.gui_capture_keyboard) {
        var moving = false;
        if (state.main_window.getKey(.w) == .press) {
            state.target_x -= fast_multiplier * sy * state.target_velocity * state.delta_time;
            state.target_y -= fast_multiplier * cy * state.target_velocity * state.delta_time;
            moving = true;
        }
        if (state.main_window.getKey(.s) == .press) {
            state.target_x += fast_multiplier * sy * state.target_velocity * state.delta_time;
            state.target_y += fast_multiplier * cy * state.target_velocity * state.delta_time;
            moving = true;
        }

        if (state.main_window.getKey(.a) == .press) {
            state.target_x -= fast_multiplier * cy * state.target_velocity * state.delta_time;
            state.target_y += fast_multiplier * sy * state.target_velocity * state.delta_time;
            moving = true;
        }

        if (state.main_window.getKey(.d) == .press) {
            state.target_x += fast_multiplier * cy * state.target_velocity * state.delta_time;
            state.target_y -= fast_multiplier * sy * state.target_velocity * state.delta_time;
            moving = true;
        }

        if (moving) {
            state.target_velocity = @min(1000, state.target_velocity + 200 * state.delta_time);
        } else {
            state.target_velocity = 0;
        }
    }

    state.target_x = @min(max_map_x, @max(0, state.target_x));
    state.target_y = @min(max_map_y, @max(0, state.target_y));

    const target_z = terrain.get_worst_elevation(state.target_x, state.target_y) + 4;

    // yaw

    const px = state.target_x + sy * state.camera_zoom * cp;
    const py = state.target_y + cy * state.camera_zoom * cp;
    const pz = target_z + sp * state.camera_zoom;

    const ch = terrain.get_worst_elevation(px, py);

    if (pz < ch + 4) {
        state.main_camera.position = math.f32x4(px, py, ch + 4, 1);
    } else {
        state.main_camera.position = math.f32x4(px, py, pz, 1);
    }

    state.main_camera.target = math.f32x4(state.target_x, state.target_y, target_z, 1);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_gui() void {
    const zone = tracy.ZoneNC(@src(), "draw_gui", 0x00_ff_00_00);
    defer zone.End();

    {
        const fb_zone = tracy.ZoneNC(@src(), "gui.backend.newFrame", 0x00800000);
        defer fb_zone.End();

        gui.backend.newFrame(@intCast(state.width), @intCast(state.height));
    }

    draw_debug();
    draw_fps();
    // gui.showDemoWindow (&state.user_demo_window);

    {
        const draw_zone = tracy.ZoneNC(@src(), "gui.backend.draw", 0x00800000);
        defer draw_zone.End();

        gui.backend.draw();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_debug() void {
    const zone = tracy.ZoneNC(@src(), "draw_debug", 0x00_ff_00_00);
    defer zone.End();

    if (state.show_debug) {
        if (gui.begin("Settings", .{})) {
            if (gui.treeNode("Terrain")) {
                _ = gui.sliderFloat("Terrain", .{
                    .v = &state.user_terrain_detail,
                    .min = 0.2,
                    .max = 1.0,
                    .cfmt = "%.2f",
                    .flags = .{
                        .always_clamp = true,
                        .no_input = true,
                    },
                });
                _ = gui.sliderFloat("Contour", .{
                    .v = &state.show_contour,
                    .min = 0.0,
                    .max = 1.0,
                    .cfmt = "%.2f",
                    .flags = .{
                        .always_clamp = true,
                        .no_input = true,
                    },
                });
                _ = gui.sliderFloat("Grid", .{
                    .v = &state.show_grid,
                    .min = 0.0,
                    .max = 1.0,
                    .cfmt = "%.2f",
                    .flags = .{
                        .always_clamp = true,
                        .no_input = true,
                    },
                });
                gui.treePop();
            }
            if (gui.treeNode("Sun")) {
                _ = gui.sliderFloat("angle", .{
                    .v = &state.sun_angle,
                    .min = 0.0,
                    .max = 80.0,
                    .cfmt = "%.0f",
                    .flags = .{
                        .always_clamp = true,
                        .no_input = true,
                    },
                });
                _ = gui.sliderFloat("direction", .{
                    .v = &state.sun_direction,
                    .min = 0.0,
                    .max = 360.0,
                    .cfmt = "%.0f",
                    .flags = .{
                        .always_clamp = true,
                        .no_input = true,
                    },
                });
                gui.treePop();
            }
        }
        gui.end();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_fps() void {
    const zone = tracy.ZoneNC(@src(), "draw_fps", 0x00_ff_00_00);
    defer zone.End();

    if (state.show_fps) {
        gui.setNextWindowSize(.{
            .w = @floatFromInt(state.width),
            .h = @floatFromInt(state.height),
        });
        gui.setNextWindowPos(.{
            .x = 0,
            .y = 0,
        });
        if (gui.begin("FPS", .{
            .flags = .{
                .no_title_bar = true,
                .no_resize = true,
                .no_move = true,
                .no_scrollbar = true,
                .no_collapse = true,
                .no_background = true,
                .no_mouse_inputs = true,
                .no_focus_on_appearing = true,
                .no_nav_inputs = true,
                .no_nav_focus = true,
            },
        })) {
            gui.text("fps: {d:0.0} / {d:0.1} ms", .{ state.fps, state.delta_time * 1000 });
            if (state.terrain_mesh[state.terrain_frame_index]) |mesh| {
                const tris = mesh.indexes.items.len / 3;
                const ratio: f32 = @as(f32, @floatFromInt(tris)) / (state.user_terrain_detail * state.target_terrain_tris);
                gui.text("terrain: {d} tris {d:0.1} {d:0.1}%", .{
                    tris,
                    state.terrain_detail,
                    ratio * 100,
                });
            }
        }
        gui.end();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_frame_times() void {}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn process_events() void {
    const events_zone = tracy.ZoneNC(@src(), "process_events", 0x00_ff_00_00);
    defer events_zone.End();

    state.gui_capture_mouse = gui.io.getWantCaptureMouse();
    state.gui_capture_keyboard = gui.io.getWantCaptureKeyboard();
    state.gui_capture_text = gui.io.getWantTextInput();

    glfw.pollEvents();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn on_key(
    window: *glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) callconv(.C) void {
    _ = scancode;

    const zone = tracy.ZoneNC(@src(), "on_key", 0x00_ff_00_00);
    defer zone.End();

    if (state.gui_capture_keyboard) {
        return;
    }

    var mod: i32 = 0;

    if (mods.shift) mod |= 1;
    if (mods.control) mod |= 2;

    // std.debug.print("Key: {} {}\n", .{ key, state.gui_capture_keyboard });

    if (key == .escape and action == .press and mod == 0) {
        _ = window.setShouldClose(true);
    } else if (key == .F1 and action == .press and mod == 0) {
        state.show_debug = !state.show_debug;
    } else if (key == .F2 and action == .press and mod == 0) {
        state.show_fps = !state.show_fps;
    } else if (key == .F3 and action == .press and mod == 0) {
        state.show_terrain = !state.show_terrain;
    } else if (key == .F4 and action == .press and mod == 0) {
        state.show_axes = !state.show_axes;
    } else if (key == .F5 and action == .press and mod == 0) {
        state.show_wireframe = !state.show_wireframe;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn on_char(window: *glfw.Window, char: u32) callconv(.C) void {
    _ = window;
    _ = char;

    const zone = tracy.ZoneNC(@src(), "on_char", 0x00_ff_00_00);
    defer zone.End();

    if (state.gui_capture_text) {
        return;
    }

    // std.debug.print("Char: {x:0>4} {}\n", .{ char, state.gui_capture_keyboard });
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn on_mouse_move(window: *glfw.Window, x: f64, y: f64) callconv(.C) void {
    _ = window;
    _ = x;
    _ = y;

    const zone = tracy.ZoneNC(@src(), "on_mouse_move", 0x00_ff_00_00);
    defer zone.End();

    if (state.gui_capture_mouse) {
        return;
    }

    // std.debug.print("Mouse: {d:0.1},{d:0.1} {}\n", .{ x, y, state.gui_capture_mouse });
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const TracyAllocator = struct {
    child_allocator: std.mem.Allocator,

    pub fn init(child_allocator: std.mem.Allocator) TracyAllocator {
        return .{
            .child_allocator = child_allocator,
        };
    }

    pub fn allocator(self: *TracyAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_ptr_align: u8,
        ra: usize,
    ) ?[*]u8 {
        const self: *TracyAllocator = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.rawAlloc(len, log2_ptr_align, ra);
        if (result != null) {
            tracy.Alloc(result.?, len);
        }
        // std.debug.print("Alloc {} : {*}\n", .{ len, result });
        return result;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_len: usize,
        ra: usize,
    ) bool {
        const self: *TracyAllocator = @ptrCast(@alignCast(ctx));
        if (self.child_allocator.rawResize(buf, log2_buf_align, new_len, ra)) {
            tracy.Free(buf.ptr);
            tracy.Alloc(buf.ptr, new_len);
            // std.debug.print("Resize {} : {*} -> {} : {*}\n", .{ buf.len, buf.ptr, new_len, buf.ptr });
            return true;
        }

        std.debug.assert(new_len > buf.len);
        return false;
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        ra: usize,
    ) void {
        const self: *TracyAllocator = @ptrCast(@alignCast(ctx));
        self.child_allocator.rawFree(buf, log2_buf_align, ra);
        // std.debug.print("Free {} : {*}\n", .{ buf.len, buf.ptr });
        tracy.Free(buf.ptr);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const shader_source = @embedFile("shader.glsl");
const terrain_source = @embedFile("terrain.glsl");

fn create_shaders() !void {
    state.basic_shader = try gfx.Shader.init(state.allocator, "basic shader", shader_source);
    state.terrain_shader = try gfx.Shader.init(state.allocator, "terrain_shader", terrain_source);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_axes() !void {
    state.axes = try Mesh.init(state.allocator, .lines);
    errdefer state.axes.deinit();

    {
        const v1 = try state.axes.addVertex(.{
            .position = .{ .x = -10000, .y = 0, .z = 0 },
            .color = .{ .r = 1, .g = 1, .b = 0 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        });
        const v2 = try state.axes.addVertex(.{
            .position = .{ .x = 10000, .y = 0, .z = 0 },
            .color = .{ .r = 1, .g = 1, .b = 0 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        });
        const v3 = try state.axes.addVertex(.{
            .position = .{ .x = 0, .y = -10000, .z = 0 },
            .color = .{ .r = 1, .g = 0, .b = 1 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        });
        const v4 = try state.axes.addVertex(.{
            .position = .{ .x = 0, .y = 10000, .z = 0 },
            .color = .{ .r = 1, .g = 0, .b = 1 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        });
        const v5 = try state.axes.addVertex(.{
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .color = .{ .r = 0, .g = 1, .b = 1 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        });
        const v6 = try state.axes.addVertex(.{
            .position = .{ .x = 0, .y = 0, .z = 10000 },
            .color = .{ .r = 0, .g = 1, .b = 1 },
            .normal = .{ .x = 0, .y = 0, .z = 0 },
        });

        try state.axes.addIndex(v1);
        try state.axes.addIndex(v2);
        try state.axes.addIndex(v3);
        try state.axes.addIndex(v4);
        try state.axes.addIndex(v5);
        try state.axes.addIndex(v6);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn begin_3d() void {
    const zone = tracy.ZoneNC(@src(), "begin_3d", 0x00_ff_00_00);
    defer zone.End();

    const model = math.identity();

    if (false) {
        std.debug.print("\n", .{});
    }

    if (false) {
        std.debug.print("model: {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ model[0][0], model[0][1], model[0][2], model[0][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ model[1][0], model[1][1], model[1][2], model[1][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ model[2][0], model[2][1], model[2][2], model[2][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ model[3][0], model[3][1], model[3][2], model[3][3] });
    }

    const view = math.lookAtLh(
        state.main_camera.position,
        state.main_camera.target,
        state.main_camera.up,
    );

    const width: f32 = @floatFromInt(state.width);
    const height: f32 = @floatFromInt(state.height);

    const aspect = width / height;

    const near: f32 = 1;
    const far: f32 = 16000;

    const projection = math.perspectiveFovLhGl(std.math.pi / 3.0, aspect, near, far);

    const camera_position = [3]f32{
        state.main_camera.position[0],
        state.main_camera.position[1],
        state.main_camera.position[2],
    };

    const sun_x = @sin(state.sun_direction / 180 * std.math.pi);
    const sun_y = @cos(state.sun_direction / 180 * std.math.pi);
    const sun_z = @sin(state.sun_angle / 180 * std.math.pi);

    const sun_direction = [3]f32{
        sun_x, sun_y, sun_z,
    };

    state.basic_shader.use();
    state.basic_shader.setUniform3f("camera", camera_position);
    state.basic_shader.setUniform3f("sun_direction", sun_direction);
    state.basic_shader.setUniform1f("show_contour", state.show_contour);
    state.basic_shader.setUniform1f("show_grid", state.show_grid);
    state.basic_shader.setUniformMat("model", model);
    state.basic_shader.setUniformMat("view", view);
    state.basic_shader.setUniformMat("projection", projection);
    state.basic_shader.end();

    state.terrain_shader.use();
    state.terrain_shader.setUniform3f("camera", camera_position);
    state.terrain_shader.setUniform3f("sun_direction", sun_direction);
    state.terrain_shader.setUniform1f("show_contour", state.show_contour);
    state.terrain_shader.setUniform1f("show_grid", state.show_grid);
    state.terrain_shader.setUniformMat("model", model);
    state.terrain_shader.setUniformMat("view", view);
    state.terrain_shader.setUniformMat("projection", projection);
    state.terrain_shader.end();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_axes() void {
    const zone = tracy.ZoneNC(@src(), "draw_axes", 0x00_ff_00_00);
    defer zone.End();

    if (state.show_axes) {
        state.basic_shader.use();
        defer state.basic_shader.end();
        state.axes.render();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_terrain() void {
    const zone = tracy.ZoneNC(@src(), "draw_terrain", 0x00_ff_00_00);
    defer zone.End();

    if (!state.show_terrain) {
        return;
    }

    if (state.terrain_generation_ready) {
        const copy_index = state.terrain_frame_index +% 1;

        if (state.terrain_mesh[copy_index]) |*mesh| {
            mesh.unmap_memory();
            mesh.copy_data();
        }

        state.terrain_generation_ready = false;
        state.terrain_frame_index +%= 1;
        terrain.request_generation();
    }

    state.terrain_shader.use();
    defer state.terrain_shader.end();

    // show the terrain from the bottom - just in case somebody goes underground
    gl.disable(gl.CULL_FACE);

    // var number_mesh_loaded : usize = 0;

    if (state.terrain_mesh[state.terrain_frame_index]) |*grid| {
        if (state.show_wireframe) {
            gl.polygonMode(gl.FRONT_AND_BACK, gl.LINE);
            grid.render();
        } else {
            gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
            grid.render();
        }
    }

    gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
    gl.enable(gl.CULL_FACE);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn opengl_debug_message(
    source: gl.Enum,
    kind: gl.Enum,
    id: gl.Enum,
    severity: gl.Enum,
    len: gl.Sizei,
    message: [*c]const u8,
    user: *const anyopaque,
) callconv(.C) void {
    _ = user;

    if (severity != gl.DEBUG_SEVERITY_NOTIFICATION) {
        const zone = tracy.ZoneNC(@src(), "opengl_debug_message", 0x00_ff_00_00);
        defer zone.End();

        const slice: []const u8 = message[0..@intCast(len)];

        const source_name = switch (source) {
            gl.DEBUG_SOURCE_API => "API",
            gl.DEBUG_SOURCE_WINDOW_SYSTEM => "WINDOW_SYSTEM",
            gl.DEBUG_SOURCE_SHADER_COMPILER => "SHADER_COMPILER",
            gl.DEBUG_SOURCE_THIRD_PARTY => "THIRD_PARTY",
            gl.DEBUG_SOURCE_APPLICATION => "APPLICATION",
            gl.DEBUG_SOURCE_OTHER => "OTHER",
            else => "Unknown",
        };

        const kind_name = switch (kind) {
            gl.DEBUG_TYPE_ERROR => "ERROR",
            gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR => "DEPRECATED_BEHAVIOR",
            gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR => "UNDEFINED_BEHAVIOR",
            gl.DEBUG_TYPE_PORTABILITY => "PORTABILITY",
            gl.DEBUG_TYPE_PERFORMANCE => "PERFORMANCE",
            gl.DEBUG_TYPE_OTHER => "OTHER",
            gl.DEBUG_TYPE_MARKER => "MARKER",
            else => "Unknown",
        };

        const severity_name = switch (severity) {
            gl.DEBUG_SEVERITY_HIGH => "High",
            gl.DEBUG_SEVERITY_MEDIUM => "Medium",
            gl.DEBUG_SEVERITY_LOW => "Low",
            gl.DEBUG_SEVERITY_NOTIFICATION => "Note",
            else => "Unknown",
        };

        const block = std.fmt.allocPrint(state.allocator, "{s} {s} {} {s} {s}", .{
            source_name,
            kind_name,
            id,
            severity_name,
            slice,
        }) catch return;
        defer state.allocator.free(block);

        std.debug.print("{s}\n", .{block});
        tracy.Message(block);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
