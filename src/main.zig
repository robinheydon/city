///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const glfw = @import("zglfw");
const gui = @import("zgui");
const opengl = @import("zopengl");

const tracy = @import("ztracy");

const fonts = @import("fonts.zig");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const State = struct {
    main_window: *glfw.Window = undefined,
    allocator: std.mem.Allocator = undefined,

    show_debug: bool = false,
    show_fps: bool = true,

    gui_capture_mouse: bool = false,
    gui_capture_keyboard: bool = false,
    gui_capture_text: bool = false,

    frame_times: [8]i64 = undefined,
    frame_time_index: usize = 0,
    frame_times_full: bool = true,
    fps: f32 = 60.0,
    last_now : i64 = 0,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub var state: State = .{};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn main() !void {
    std.debug.print("City\n", .{});

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 6;

    glfw.windowHintTyped(.context_version_major, gl_major);
    glfw.windowHintTyped(.context_version_minor, gl_minor);
    glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
    glfw.windowHintTyped(.opengl_forward_compat, true);
    glfw.windowHintTyped(.client_api, .opengl_api);
    glfw.windowHintTyped(.doublebuffer, true);

    state.main_window = try glfw.Window.create(1280, 720, "City", null);
    defer state.main_window.destroy();

    glfw.makeContextCurrent(state.main_window);
    glfw.swapInterval(1);

    _ = state.main_window.setKeyCallback(on_key);
    _ = state.main_window.setCharCallback(on_char);
    _ = state.main_window.setCursorPosCallback(on_mouse_move);

    try opengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
    const gl = opengl.bindings;

    gl.debugMessageCallback(opengl_debug_message, null);
    gl.enable(opengl.bindings.DEBUG_OUTPUT);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var tracy_allocator = TracyAllocator{ .child_allocator = gpa.allocator() };
    state.allocator = tracy_allocator.allocator();

    gui.init(state.allocator);
    defer gui.deinit();

    gui.backend.init(state.main_window);
    defer gui.backend.deinit();

    _ = gui.io.addFontFromMemory(fonts.atkinson_regular, 24);

    gui.getStyle().scaleAllSizes(2);

    while (!state.main_window.shouldClose()) {
        tracy.FrameMark();

        const dt = calculate_delta_time ();
        _ = dt;

        {
            const zone = tracy.ZoneNC(@src(), "gl.clearBufferfv", 0x00_80_80_80);
            defer zone.End();
            gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.2, 0.2, 0.2, 1 });
        }

        draw_gui();

        {
            const zone = tracy.ZoneNC(@src(), "swapBuffers", 0x00_00_ff_00);
            defer zone.End();
            state.main_window.swapBuffers();
        }

        process_events();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn calculate_delta_time() f32 {
    const zone = tracy.ZoneNC(@src(), "calculate_delta_time", 0x00_ff_00_00);
    defer zone.End();

    const now = std.time.microTimestamp ();
    const delta = now - state.last_now;
    state.last_now = now;

    const dt = @as (f32, @floatFromInt (delta)) / std.time.us_per_s;

    state.frame_times[state.frame_time_index] = delta;
    state.frame_time_index += 1;
    if (state.frame_time_index == state.frame_times.len)
    {
        state.frame_time_index = 0;
        state.frame_times_full = true;
    }

    if (state.frame_times_full)
    {
        var total: i64 = 0;
        for (0..state.frame_times.len) |i|
        {
            total += state.frame_times[i];
        }
        const average : f32 = @as (f32, @floatFromInt (total)) / state.frame_times.len / std.time.us_per_s;
        state.fps = 1 / average;
    }

    return dt;
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn draw_gui() void {
    const zone = tracy.ZoneNC(@src(), "draw_gui", 0x00_ff_00_00);
    defer zone.End();

    const fb_size_zone = tracy.ZoneNC(@src(), "getFramebufferSize", 0x00800000);
    const fb_size = state.main_window.getFramebufferSize();
    fb_size_zone.End();

    const fb_zone = tracy.ZoneNC(@src(), "gui.backend.newFrame", 0x00800000);
    gui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));
    fb_zone.End();

    draw_debug();
    draw_fps();

    // if (state.show_demo) {
    // gui.showDemoWindow (&state.show_demo);
    // }

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
        gui.setNextWindowSize (.{
            .w = 200,
            .h = 50,
        });
        gui.setNextWindowPos (.{
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
        }
        gui.end ();
    }
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

fn on_key(window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
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

fn opengl_debug_message(
    source: opengl.bindings.Enum,
    kind: opengl.bindings.Enum,
    id: opengl.bindings.Enum,
    severity: opengl.bindings.Enum,
    len: opengl.bindings.Sizei,
    message: [*c]const u8,
    user: *const anyopaque,
) callconv(.C) void {
    _ = user;

    const zone = tracy.ZoneNC(@src(), "opengl_debug_message", 0x00_ff_00_00);
    defer zone.End();

    const slice: []const u8 = message[0..@intCast(len)];

    const block = std.fmt.allocPrint (state.allocator, "{} {} {} {} {s}", .{
        source,
        kind,
        id,
        severity,
        slice,
    }) catch return;
    defer state.allocator.free (block);

    std.debug.print ("{s}\n", .{block});
    tracy.Message (block);
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
