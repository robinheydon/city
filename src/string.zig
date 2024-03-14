///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

var counter: usize = 0;
var string_memory: std.ArrayList(u8) = undefined;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn init(allocator: std.mem.Allocator) !void {
    if (counter != 0) {
        return error.AlreadyAllocated;
    }
    counter += 1;
    string_memory = try std.ArrayList(u8).initCapacity(allocator, 256 * 1024);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn deinit() void {
    std.debug.assert(counter == 1);
    counter -= 1;
    string_memory.deinit();
    string_memory = undefined;
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn intern(slice: []const u8) String {
    if (std.mem.indexOf(u8, string_memory.items, slice)) |index| {
        return .{
            .index = @truncate(index),
            .len = @truncate(slice.len),
        };
    }
    const index = string_memory.items.len;
    string_memory.appendSlice(slice) catch {
        std.debug.print("ERROR: Out of memory in intern\n", .{});
        return .{
            .index = 0,
            .len = 0,
        };
    };
    return .{
        .index = @truncate(index),
        .len = @truncate(slice.len),
    };
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn eql(lhs: String, rhs: String) bool {
    return (lhs.index == rhs.index and lhs.len == rhs.len);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn dump(writer: anytype) !void {
    try writer.print("\"{}\"", .{
        std.zig.fmtEscapes(string_memory.items),
    });
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const String = packed struct {
    index: u32 = 0,
    len: u32 = 0,

    pub fn get(self: String) []const u8 {
        const index = self.index;
        const len = self.len;
        return string_memory.items[index .. index + len];
    }

    pub fn concat(lhs: String, rhs: String) !String {
        if (lhs.index + lhs.len == rhs.index) {
            return .{
                .index = lhs.index,
                .len = @truncate(lhs.len + rhs.len),
            };
        }

        const left = lhs.get();
        const right = rhs.get();

        const index = string_memory.items.len;
        try string_memory.appendSlice(left);
        try string_memory.appendSlice(right);
        return .{
            .index = @truncate(index),
            .len = @truncate(left.len + right.len),
        };
    }

    pub fn serialize(alloc: std.mem.Allocator, self: *String) error{OutOfMemory}![]const u8 {
        return std.fmt.allocPrint(alloc, "[{}]{'}", .{ self.len, self });
    }

    pub fn format(self: String, fmt: anytype, _: anytype, writer: anytype) !void {
        var use_single_quotes = false;
        var use_double_quotes = false;

        for (fmt) |ch| {
            if (ch == '\'') {
                use_single_quotes = true;
                use_double_quotes = false;
            } else if (ch == '\"') {
                use_single_quotes = false;
                use_double_quotes = true;
            }
        }

        const slice = self.get();
        if (use_single_quotes) {
            try writer.print("\'{'}\'", .{std.zig.fmtEscapes(slice)});
        } else if (use_double_quotes) {
            try writer.print("\"{}\"", .{std.zig.fmtEscapes(slice)});
        } else {
            try writer.writeAll(slice);
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn string_lt(_: void, lhs: String, rhs: String) bool {
    const lhs_slice = lhs.get();
    const rhs_slice = rhs.get();

    return std.mem.order(u8, lhs_slice, rhs_slice) == .lt;
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "string: init" {
    try init(std.testing.allocator);
    defer deinit();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "string: format" {
    try init(std.testing.allocator);
    defer deinit();

    const onetwo = try intern("one's \"two\"\n");

    try std.testing.expectFmt("one's \"two\"\n", "{}", .{onetwo});
    try std.testing.expectFmt("'one\\'s \"two\"\\n'", "{'}", .{onetwo});
    try std.testing.expectFmt("\"one's \\\"two\\\"\\n\"", "{\"}", .{onetwo});
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "string: hello world" {
    try init(std.testing.allocator);
    defer deinit();

    const hello = try intern("Hello");
    const world = try intern("World");
    const hello2 = try intern("Hello");
    const hell = try intern("Hell");

    const hi = hello.get();
    try std.testing.expectFmt("Hello", "{s}", .{hi});

    const monde = world.get();
    try std.testing.expectFmt("World", "{s}", .{monde});

    const hi2 = hello2.get();
    try std.testing.expectFmt("Hello", "{s}", .{hi2});

    try std.testing.expectEqual(hi, hi2);

    try std.testing.expectEqual(hell.index, hello.index);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "string: concatination" {
    try init(std.testing.allocator);
    defer deinit();

    const hello = try intern("Hello");
    const comma = try intern(",");
    const space = try intern(" ");
    const world = try intern("World");
    const bang = try intern("!");

    const hc = try hello.concat(comma);
    const hcs = try hc.concat(space);
    const hcsw = try hcs.concat(world);
    const hcswb = try hcsw.concat(bang);

    try std.testing.expectFmt("Hello, World!", "{s}", .{hcswb});

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    try dump(writer);

    try std.testing.expectFmt("\"Hello, World!\"", "{s}", .{buffer.items});
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "string: hard concatination" {
    try init(std.testing.allocator);
    defer deinit();

    const space = try intern(" ");
    const bang = try intern("!");
    const comma = try intern(",");
    const hello = try intern("Hello");
    const world = try intern("World");

    const hc = try hello.concat(comma);
    const hcs = try hc.concat(space);
    const hcsw = try hcs.concat(world);
    const hcswb = try hcsw.concat(bang);

    try std.testing.expectFmt("Hello, World!", "{}", .{hcswb});

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    try dump(writer);

    try std.testing.expectFmt("\" !,HelloWorldHello,Hello, Hello, WorldHello, World!\"", "{s}", .{buffer.items});
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "string: double init" {
    try init(std.testing.allocator);
    defer deinit();

    try std.testing.expectError(error.AlreadyAllocated, init(std.testing.allocator));
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
