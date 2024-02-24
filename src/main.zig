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
const rand = random.rand;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const TerrainMesh = gfx.Mesh(gfx.TerrainVertex);
const Mesh = gfx.Mesh(gfx.Vertex);

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const max_map_x = 64 * 1024;
const max_map_y = 64 * 1024;

const max_grid_x = max_map_x / 1024;
const max_grid_y = max_map_y / 1024;

const terrain_cell_size = 16;

const max_terrain_lod = 6;

pub const State = struct {
    main_window: *glfw.Window = undefined,
    allocator: std.mem.Allocator = undefined,

    show_debug: bool = false,
    show_fps: bool = true,
    show_terrain: bool = true,
    show_axes: bool = false,
    show_wireframe: bool = false,
    show_grid: bool = false,

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

    target_x: f32 = 32 * 1024,
    target_y: f32 = 32 * 1024,
    camera_rotation: f32 = 0,
    camera_elevation: f32 = 1000,
    camera_angle: f32 = 45,

    isaac64: std.rand.Isaac64 = undefined, // rand.zig
    random: std.rand.Random = undefined,

    width: i32 = undefined,
    height: i32 = undefined,

    height_map: [max_map_y / terrain_cell_size + 1][max_map_x / terrain_cell_size + 1]f32 = undefined,

    terrain_mesh: [max_grid_y][max_grid_x][max_terrain_lod]?TerrainMesh = undefined,
    terrain_lines: [max_grid_y][max_grid_x][max_terrain_lod]?TerrainMesh = undefined,
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
    defer std.debug.assert(gpa.deinit() == .ok);

    var tracy_allocator = TracyAllocator{ .child_allocator = gpa.allocator() };
    state.allocator = tracy_allocator.allocator();

    std.debug.print("City\n", .{});

    random.init();

    stbi.init(state.allocator);
    defer stbi.deinit();

    try init_height_map();

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

    glfw.swapInterval(0);

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

    try create_shaders();

    try create_terrain();
    defer delete_terrain();

    try create_axes();
    defer state.axes.deinit();

    gl.enable(gl.CULL_FACE);
    gl.cullFace(gl.BACK);
    gl.frontFace(gl.CW);
    gl.depthFunc(gl.LEQUAL);
    gl.enable(gl.DEPTH_TEST);

    state.fade_to_color[0] = 0.4;
    state.fade_to_color[1] = 0.4;
    state.fade_to_color[2] = 0.4;

    main_start_zone.End();

    reset_delta_time();

    while (!state.main_window.shouldClose()) {
        tracy.FrameMark();

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

fn init_height_map() !void {
    var map = try stbi.Image.loadFromFile("media/16mgrid.png", 1);
    defer map.deinit();

    for (0..max_map_x / terrain_cell_size + 1) |y| {
        for (0..max_map_y / terrain_cell_size + 1) |x| {
            state.height_map[y][x] = 0;
        }
    }

    var map_data: []u16 = undefined;
    map_data.ptr = @alignCast(@ptrCast(map.data.ptr));
    map_data.len = map.data.len / 2;

    var max_height: f32 = 0;
    var min_height: f32 = 65535;

    for (0..max_map_x / terrain_cell_size + 1) |y| {
        for (0..max_map_x / terrain_cell_size + 1) |x| {
            if (x < map.width and y < map.height) {
                const height: f32 = @as(f32, @floatFromInt(map_data[y * map.width + x])) / 60;
                state.height_map[y][x] = height;
                max_height = @max(height, max_height);
                if (height > 0) {
                    min_height = @min(height, min_height);
                }
            } else {
                state.height_map[y][x] = 0;
            }
        }
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
    const fast_multiplier: f32 = if (state.main_window.getKey(.left_shift) == .press) 4 else 1;

    if (!state.gui_capture_keyboard) {
        if (state.main_window.getKey(.q) == .press) {
            state.camera_rotation += fast_multiplier * state.delta_time;
        }

        if (state.main_window.getKey(.e) == .press) {
            state.camera_rotation -= fast_multiplier * state.delta_time;
        }

        if (state.main_window.getKey(.f) == .press) {
            state.camera_angle = @max(5, state.camera_angle - fast_multiplier * 16 * state.delta_time);
        }

        if (state.main_window.getKey(.r) == .press) {
            state.camera_angle = @min(170, state.camera_angle + fast_multiplier * 16 * state.delta_time);
        }

        if (state.main_window.getKey(.z) == .press) {
            state.camera_elevation = @max(1, state.camera_elevation - fast_multiplier * 128 * state.delta_time);
        }

        if (state.main_window.getKey(.x) == .press) {
            state.camera_elevation = @min(2000, state.camera_elevation + fast_multiplier * 128 * state.delta_time);
        }
    }

    const sa: f32 = @floatCast(@sin(state.camera_rotation));
    const ca: f32 = @floatCast(@cos(state.camera_rotation));

    if (!state.gui_capture_keyboard) {
        if (state.main_window.getKey(.w) == .press) {
            state.target_x -= fast_multiplier * sa * state.camera_elevation / 100;
            state.target_y -= fast_multiplier * ca * state.camera_elevation / 100;
        }

        if (state.main_window.getKey(.s) == .press) {
            state.target_x += fast_multiplier * sa * state.camera_elevation / 100;
            state.target_y += fast_multiplier * ca * state.camera_elevation / 100;
        }

        if (state.main_window.getKey(.a) == .press) {
            state.target_x -= fast_multiplier * ca * state.camera_elevation / 100;
            state.target_y += fast_multiplier * sa * state.camera_elevation / 100;
        }

        if (state.main_window.getKey(.d) == .press) {
            state.target_x += fast_multiplier * ca * state.camera_elevation / 100;
            state.target_y -= fast_multiplier * sa * state.camera_elevation / 100;
        }
    }

    if (state.main_window.getKey(.t) == .press) {
        state.target_x = 32 * 1024;
        state.target_y = 32 * 1024;
        state.camera_rotation = 0;
        state.camera_elevation = 1000;
        state.camera_angle = 45;
    }

    const cx = state.target_x + sa * state.camera_elevation;
    const cy = state.target_y + ca * state.camera_elevation;
    const cz = state.camera_elevation;

    state.main_camera.position = .{ cx, cy, cz, 1 };

    state.main_camera.target = .{
        state.target_x,
        state.target_y,
        1 + @cos(state.camera_angle / 180 * std.math.pi) * state.camera_elevation,
        1,
    };
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_gui() void {
    const zone = tracy.ZoneNC(@src(), "draw_gui", 0x00_ff_00_00);
    defer zone.End();

    const fb_zone = tracy.ZoneNC(@src(), "gui.backend.newFrame", 0x00800000);
    gui.backend.newFrame(@intCast(state.width), @intCast(state.height));
    fb_zone.End();

    draw_debug();
    draw_fps();

    const draw_zone = tracy.ZoneNC(@src(), "gui.backend.draw", 0x00800000);
    gui.backend.draw();
    draw_zone.End();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_debug() void {
    const zone = tracy.ZoneNC(@src(), "draw_debug", 0x00_ff_00_00);
    defer zone.End();

    if (state.show_debug) {
        if (gui.begin("Debug", .{})) {
            if (gui.button("Hello", .{})) {
                std.debug.print("Hello Button\n", .{});
            }

            var input_text: [32]u8 = undefined;
            input_text[0] = 0;

            if (gui.inputText("Input", .{
                .buf = &input_text,
                .flags = .{
                    .enter_returns_true = true,
                    .escape_clears_all = true,
                    .callback_completion = true,
                },
                .callback = input_text_callback,
            })) {
                const len = std.mem.indexOfSentinel(u8, '\x00', @ptrCast(&input_text));
                const slice = std.mem.trim(u8, input_text[0..len], " ");
                std.debug.print("'{'}'\n", .{std.zig.fmtEscapes(slice)});
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
            gui.text("fps: {d:0.0}", .{state.fps});
            gui.text("target_x: {d:0.3}", .{state.target_x});
            gui.text("target_y: {d:0.3}", .{state.target_y});
            gui.text("camera_rotation: {d:0.3}", .{state.camera_rotation});
            gui.text("camera_elevation: {d:0.3}", .{state.camera_elevation});
            gui.text("camera_angle: {d:0.3}", .{state.camera_angle});
        }
        gui.end();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_frame_times () void {
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn input_text_callback(data: *gui.InputTextCallbackData) i32 {
    const zone = tracy.ZoneNC(@src(), "input_text_callback", 0x00_ff_00_00);
    defer zone.End();

    const slice = data.buf[0..@intCast(data.buf_text_len)];
    std.debug.print("'{'}'\n", .{std.zig.fmtEscapes(slice)});
    return 0;
}

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
    } else if (key == .F6 and action == .press and mod == 0) {
        state.show_grid = !state.show_grid;
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
        tracy.Free(buf.ptr);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const shader_source = @embedFile("shader.glsl");
const terrain_source = @embedFile("terrain.glsl");

fn create_shaders() !void {
    state.basic_shader = try gfx.Shader.init(state.allocator, shader_source);
    state.terrain_shader = try gfx.Shader.init(state.allocator, terrain_source);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_terrain() !void {
    for (0..max_grid_y) |gy| {
        for (0..max_grid_x) |gx| {
            for (0..max_terrain_lod) |i| {
                state.terrain_mesh[gy][gx][i] = null;
                state.terrain_lines[gy][gx][i] = null;
            }
            try create_terrain_grid (gx, gy, max_terrain_lod - 1);
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_terrain_grid (gx: usize, gy: usize, lod: usize) !void
{
    if (state.terrain_mesh[gy][gx][lod] == null)
    {
        var mesh1 = try gfx.Mesh(gfx.TerrainVertex).init(
            state.allocator,
            .triangles,
        );
        errdefer mesh1.deinit ();

        const mesh2 = try gfx.Mesh(gfx.TerrainVertex).init(
            state.allocator,
            .lines,
        );

        state.terrain_mesh[gy][gx][lod] = mesh1;
        state.terrain_lines[gy][gx][lod] = mesh2;

        var vertexes: [65 * 65]u32 = undefined;

        const max = @shrExact(@as(u32, @intCast(1024 / 16)), @intCast(lod)) + 1;
        const step = @as(u32, 1) << @intCast(lod);

        for (0..max) |x| {
            for (0..max) |y| {
                const fx: f32 = @floatFromInt(x * terrain_cell_size * step + gx * 1024);
                const fy: f32 = @floatFromInt(y * terrain_cell_size * step + gy * 1024);
                const h = state.height_map[y * step + gy * 64][x * step + gx * 64];

                var r: f32 = 0;
                var g: f32 = 0;
                var b: f32 = 0;

                if (h == 0) {
                    b = 1;
                } else {
                    r = h / 1500;
                    g = 0.8;
                    b = h / 1500;
                }

                vertexes[x * max + y] = try state.terrain_mesh[gy][gx][lod].?.addVertex(.{
                    .pos = .{ .x = fx, .y = fy, .z = h },
                    .col = .{ .r = r, .g = g, .b = b },
                });
            }
        }

        for (0..max / 2) |hx| {
            for (0..max / 2) |hy| {
                const x = hx * 2;
                const y = hy * 2;
                const v1 = vertexes[x * max + y];
                const v2 = v1 + 1;
                const v3 = v1 + 2;
                const v4 = v1 + max + 0;
                const v5 = v1 + max + 1;
                const v6 = v1 + max + 2;
                const v7 = v1 + max * 2 + 0;
                const v8 = v1 + max * 2 + 1;
                const v9 = v1 + max * 2 + 2;

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v2);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v1);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v3);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v2);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v6);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v3);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v9);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v6);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v8);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v9);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v7);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v8);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v4);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v7);

                try state.terrain_mesh[gy][gx][lod].?.addIndex(v5);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v1);
                try state.terrain_mesh[gy][gx][lod].?.addIndex(v4);
            }
        }

        for (0..max) |x| {
            for (0..max) |y| {
                const fx: f32 = @floatFromInt(x * terrain_cell_size * step + gx * 1024);
                const fy: f32 = @floatFromInt(y * terrain_cell_size * step + gy * 1024);
                const h = state.height_map[y * step + gy * 64][x * step + gx * 64];

                vertexes[x * max + y] = try state.terrain_lines[gy][gx][lod].?.addVertex(.{
                    .pos = .{ .x = fx, .y = fy, .z = h + 0 },
                    .col = .{
                        .r = 0,
                        .g = 0,
                        .b = 0,
                    },
                });
            }
        }

        for (0..max - 1) |x| {
            for (0..max - 1) |y| {
                const v1 = vertexes[x * max + y];
                const v2 = v1 + 1;
                const v3 = v1 + max;
                const v4 = v1 + max + 1;

                try state.terrain_lines[gy][gx][lod].?.addIndex(v1);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v2);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v2);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v4);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v4);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v3);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v3);
                try state.terrain_lines[gy][gx][lod].?.addIndex(v1);
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn delete_terrain() void {
    for (0..max_grid_y) |gy| {
        for (0..max_grid_x) |gx| {
            for (0..max_terrain_lod) |i| {
                if (state.terrain_mesh[gy][gx][i]) |*grid|
                {
                    grid.deinit();
                }
                if (state.terrain_lines[gy][gx][i]) |*grid|
                {
                    grid.deinit();
                }
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_axes() !void {
    state.axes = try Mesh.init(state.allocator, .lines);
    errdefer state.axes.deinit();

    {
        const v1 = try state.axes.addVertex(.{
            .pos = .{ .x = -10000, .y = 0, .z = 0 },
            .col = .{ .r = 1, .g = 1, .b = 0 },
        });
        const v2 = try state.axes.addVertex(.{
            .pos = .{ .x = 10000, .y = 0, .z = 0 },
            .col = .{ .r = 1, .g = 1, .b = 0 },
        });
        const v3 = try state.axes.addVertex(.{
            .pos = .{ .x = 0, .y = -10000, .z = 0 },
            .col = .{ .r = 1, .g = 0, .b = 1 },
        });
        const v4 = try state.axes.addVertex(.{
            .pos = .{ .x = 0, .y = 10000, .z = 0 },
            .col = .{ .r = 1, .g = 0, .b = 1 },
        });
        const v5 = try state.axes.addVertex(.{
            .pos = .{ .x = 0, .y = 0, .z = 0 },
            .col = .{ .r = 0, .g = 1, .b = 1 },
        });
        const v6 = try state.axes.addVertex(.{
            .pos = .{ .x = 0, .y = 0, .z = 10000 },
            .col = .{ .r = 0, .g = 1, .b = 1 },
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
    // const view : math.Mat = .{
    // .{1, 0, 0, 0},
    // .{0, 1, 0, 0},
    // .{0, 0, 1, 0},
    // .{-0.5, -2, 4, 1},
    // };

    if (false) {
        std.debug.print("pos  : {d:7.2} {d:7.2} {d:7.2} {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ state.main_camera.position[0], state.main_camera.position[1], state.main_camera.position[2], state.main_camera.position[3], state.now, @sin(state.now), @cos(state.now) });
        std.debug.print("view : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ view[0][0], view[0][1], view[0][2], view[0][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ view[1][0], view[1][1], view[1][2], view[1][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ view[2][0], view[2][1], view[2][2], view[2][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ view[3][0], view[3][1], view[3][2], view[3][3] });
    }

    const width: f32 = @floatFromInt(state.width);
    const height: f32 = @floatFromInt(state.height);

    const aspect = width / height;

    const near: f32 = 0.1;
    const far: f32 = 20000;

    const projection = math.perspectiveFovLhGl(std.math.pi / 3.0, aspect, near, far);

    if (false) {
        std.debug.print("proj : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ projection[0][0], projection[0][1], projection[0][2], projection[0][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ projection[1][0], projection[1][1], projection[1][2], projection[1][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ projection[2][0], projection[2][1], projection[2][2], projection[2][3] });
        std.debug.print("     : {d:7.2} {d:7.2} {d:7.2} {d:7.2}\n", .{ projection[3][0], projection[3][1], projection[3][2], projection[3][3] });
    }

    const camera_pos: [3]f32 = .{
        state.main_camera.position[0],
        state.main_camera.position[1],
        state.main_camera.position[2],
    };

    state.basic_shader.use();
    state.basic_shader.setUniform3f("camera_pos", camera_pos);
    state.basic_shader.setUniformMat("model", model);
    state.basic_shader.setUniformMat("view", view);
    state.basic_shader.setUniformMat("projection", projection);
    state.basic_shader.end();

    state.terrain_shader.use();
    state.terrain_shader.setUniform3f("camera_pos", camera_pos);
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

    state.terrain_shader.use();
    defer state.terrain_shader.end();

    // show the terrain from the bottom - just in case somebody goes underground
    gl.disable(gl.CULL_FACE);

    var number_mesh_loaded : usize = 0;

    for (0..64) |gy|
    {
        for (0..64) |gx|
        {
            const dx = state.main_camera.position[0] - @as (f32, @floatFromInt (gx * 1024 + 512));
            const dy = state.main_camera.position[1] - @as (f32, @floatFromInt (gy * 1024 + 512));

            const dist = @sqrt (dx * dx + dy * dy);

            var lod : usize = 0;

            if (dist < 3000) {
                lod = 0;
            } else if (dist < 4000) {
                lod = 1;
            } else if (dist < 5000) {
                lod = 2;
            } else if (dist < 6000) {
                lod = 3;
            } else if (dist < 7000) {
                lod = 4;
            } else if (dist < 16000) {
                lod = 5;
            }
            else {
                continue;
            }

            if (state.terrain_mesh[gy][gx][lod] == null)
            {
                if (number_mesh_loaded < 16)
                {
                    var this_lod = lod;
                    while (this_lod < max_terrain_lod)
                    {
                        create_terrain_grid (gx, gy, this_lod) catch {};
                        number_mesh_loaded += 1;
                        this_lod += 1;
                    }
                }
                else
                {
                    while (lod < max_terrain_lod)
                    {
                        if (state.terrain_mesh[gy][gx][lod] != null)
                        {
                            break;
                        }
                        lod += 1;
                    }
                }
            }

            if (gy >= 0 and gy < max_grid_y and gx >= 0 and gx <= max_grid_x)
            {
                if (state.show_wireframe) {
                    if (state.terrain_mesh[gy][gx][lod]) |*grid|
                    {
                        gl.polygonMode(gl.FRONT_AND_BACK, gl.LINE);
                        grid.render();
                    }
                } else {
                    if (state.terrain_mesh[gy][gx][lod]) |*grid|
                    {
                        gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
                        grid.render();
                    }
                    if (state.show_grid) {
                        if (state.terrain_lines[gy][gx][lod]) |*grid|
                        {
                            gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
                            grid.render ();
                        }
                    }
                }
            }
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

    if (severity == gl.DEBUG_SEVERITY_HIGH or severity == gl.DEBUG_SEVERITY_MEDIUM or severity == gl.DEBUG_SEVERITY_LOW) {
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
