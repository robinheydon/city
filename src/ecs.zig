///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const meta = std.meta;

const string = @import("string.zig");
const String = string.String;
const intern = string.intern;

const fmtEscapes = std.zig.fmtEscapes;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 2 };

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "ecs version string" {
    try std.testing.expectFmt("0.0.2", "{}", .{version});
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const EntityIndex = u24;
const EntityGeneration = u8;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn get_component_info(comptime T: type) *TypeInfo(T) {
    var tip = &(struct {
        var ti: TypeInfo(T) = .{};
    }.ti);

    if (tip.self != @intFromPtr(tip)) {
        tip.init();
    }

    return tip;
}

fn TypeInfo(comptime T: type) type {
    return struct {
        initialized: bool = false,
        size: usize = undefined,
        alignment: usize = undefined,
        name: String = undefined,
        label: ?String = null,
        self: usize = 0,
        fields: std.ArrayListUnmanaged(ComponentField) = .{},
        indexes: std.AutoArrayHashMapUnmanaged(EntityIndex, usize) = .{},
        len: usize = 0,
        data: std.ArrayListUnmanaged(u8) = .{},

        const Self = @This();

        pub fn init(self: *Self) void {
            self.initialized = true;
            self.size = @sizeOf(T);
            self.alignment = @alignOf(T);
            self.name = intern(@typeName(T));
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        fn get_offset(self: Self, index: usize) usize {
            return index * self.size;
        }

        fn get_index(self: Self, entity_index: EntityIndex) ?usize {
            const value = self.indexes.get(entity_index);
            return value;
        }

        pub fn set(self: *Self, alloc: std.mem.Allocator, entity_index: EntityIndex, value: T) !void {
            const src = @as([*]const u8, @ptrFromInt(@intFromPtr(&value)));
            try self.set_data(alloc, entity_index, src);
        }

        pub fn set_data(
            self: *Self,
            alloc: std.mem.Allocator,
            entity_index: EntityIndex,
            data: [*]const u8,
        ) !void {
            if (self.get_index(entity_index)) |index| {
                const offset = self.get_offset(index);
                const dst = self.data.items[offset .. offset + self.size];
                @memcpy(dst, data);
                return;
            }
            const last_len = self.data.items.len;

            try self.data.appendSlice(alloc, data[0..self.size]);
            errdefer self.data.items.len = last_len;

            try self.indexes.put(alloc, entity_index, self.len);

            self.len += 1;
        }

        pub fn get(self: Self, entity_index: EntityIndex) ?T {
            if (self.get_index(entity_index)) |index| {
                const offset = self.get_offset(index);
                const src = self.data.items[offset .. offset + self.size];
                var value: T = undefined;
                const dst = @as([*]u8, @ptrFromInt(@intFromPtr(&value)))[0..self.size];
                @memcpy(dst, src);
                return value;
            }
            return null;
        }

        pub fn get_data(self: Self, entity_index: EntityIndex) ?[]const u8 {
            if (self.get_index(entity_index)) |index| {
                const offset = self.get_offset(index);
                const src = self.data.items[offset .. offset + self.size];
                var value: []u8 = undefined;
                value = src;
                return value;
            }
            return null;
        }

        pub fn format(self: Self, _: anytype, _: anytype, writer: anytype) !void {
            try writer.print("T({})", .{self.name});
        }
    };
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const EntityId = packed struct(u32) {
    index: EntityIndex = max_index,
    generation: EntityGeneration = max_generation,

    ////////////////////////////////////////

    pub fn less_than(ctx: void, lhs: EntityId, rhs: EntityId) bool {
        _ = ctx;
        return lhs.index < rhs.index;
    }

    ////////////////////////////////////////

    pub fn format(self: EntityId, fmt: []const u8, opt: anytype, writer: anytype) !void {
        _ = fmt;
        _ = opt;

        if ((self.generation == max_generation) and (self.index == max_index)) {
            try writer.print("E(null)", .{});
        } else {
            try writer.print("E({x}:{x})", .{ self.generation, self.index });
        }
    }
};

////////////////////////////////////////

const max_index = std.math.maxInt(EntityIndex);
const max_generation = std.math.maxInt(EntityGeneration);
const GenerationArray = std.ArrayListUnmanaged(EntityData);

////////////////////////////////////////

const EntityData = struct {
    index: EntityIndex,
    generation: EntityGeneration,
    immortal: bool,
};

////////////////////////////////////////

const ComponentField = struct {
    name: String,
    offset: usize = 0,
    size: usize = 0,
    array_length: ?usize = null,
    kind: usize = 0,
    value: ?u64 = null,
};

////////////////////////////////////////

pub fn init(allocator: std.mem.Allocator) !World {
    var world = World{
        .alloc = allocator,
        .next_deleted = max_index,
    };

    try string.init(allocator);

    world.null = try world.register_component(void, null);
    world.bool = try world.register_component(bool, null);
    world.u8 = try world.register_component(u8, null);
    world.u8 = try world.register_component(u8, null);
    world.u16 = try world.register_component(u16, null);
    world.u24 = try world.register_component(u24, null);
    world.u32 = try world.register_component(u32, null);
    world.u48 = try world.register_component(u48, null);
    world.u64 = try world.register_component(u64, null);
    world.i8 = try world.register_component(i8, null);
    world.i16 = try world.register_component(i16, null);
    world.i24 = try world.register_component(i24, null);
    world.i32 = try world.register_component(i32, null);
    world.i48 = try world.register_component(i48, null);
    world.i64 = try world.register_component(i64, null);
    world.f32 = try world.register_component(f32, null);
    world.f64 = try world.register_component(f64, null);
    world.usize = try world.register_component(usize, null);
    world.String = try world.register_component(String, "String");
    world.EntityId = try world.register_component(EntityId, "EntityId");

    return world;
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Entity = struct {
    world: *World,
    id: EntityId = .{},

    pub fn set_label(self: Entity, label: String) void {
        self.world.set_label(self.id, label);
    }

    pub fn get_label(self: Entity) ?String {
        return self.world.get_label(self.id);
    }

    pub fn destroy(self: Entity) void {
        self.world.destroy(self.id);
    }

    pub fn set(self: Entity, comptime value: anytype) void {
        self.world.set(self.id, value);
    }

    pub fn get(self: Entity, comptime T: type) ?T {
        return self.world.get(self.id, T);
    }

    pub fn format(self: Entity, _: []const u8, _: anytype, writer: anytype) !void {
        try writer.print("{}", .{self.id});
        if (self.get_label()) |label| {
            try writer.print(" {'}", .{label});
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const World = struct {
    alloc: std.mem.Allocator,
    generations: GenerationArray = .{},
    num_deleted: usize = 0,
    next_deleted: EntityIndex = max_index,
    components: std.AutoArrayHashMapUnmanaged(usize, void) = .{},

    null: usize = undefined,
    bool: usize = undefined,
    u8: usize = undefined,
    u16: usize = undefined,
    u24: usize = undefined,
    u32: usize = undefined,
    u48: usize = undefined,
    u64: usize = undefined,
    i8: usize = undefined,
    i16: usize = undefined,
    i24: usize = undefined,
    i32: usize = undefined,
    i48: usize = undefined,
    i64: usize = undefined,
    f32: usize = undefined,
    f64: usize = undefined,
    usize: usize = undefined,
    String: usize = undefined,
    EntityId: usize = undefined,

    ////////////////////////////////////////

    pub fn deinit(self: *World) void {
        self.generations.deinit(self.alloc);
        self.components.deinit(self.alloc);
        string.deinit();
    }

    ////////////////////////////////////////

    pub fn create_with_immortal(self: *World, immortal: bool) Entity {
        if (self.num_deleted > 0) {
            const index = self.next_deleted;
            const old_e = self.generations.items[index];
            self.next_deleted = old_e.index;
            self.num_deleted -= 1;
            const new_e = Entity{
                .world = self,
                .id = .{ .index = index, .generation = old_e.generation },
            };
            self.generations.items[index] = EntityData{ .index = new_e.id.index, .generation = new_e.id.generation, .immortal = immortal };
            return new_e;
        } else {
            const index = self.generations.items.len;

            if (index < max_index) {
                const ed = EntityData{ .index = @truncate(index), .generation = 0, .immortal = immortal };
                self.generations.append(self.alloc, ed) catch |err| {
                    std.log.err("Cannot extent generations array {}", .{err});
                    return .{ .world = self, .id = .{} };
                };

                return .{
                    .world = self,
                    .id = .{ .index = ed.index, .generation = ed.generation },
                };
            } else {
                return .{ .world = self, .id = .{} };
            }
        }
    }

    ////////////////////////////////////////

    pub fn create(self: *World) Entity {
        return self.create_with_immortal(false);
    }

    ////////////////////////////////////////

    pub fn valid_entity(self: World, entity: EntityId) bool {
        return ((entity.index != max_index) and
            (entity.generation != max_generation) and
            (entity.index < self.generations.items.len) and
            (self.generations.items[entity.index].generation == entity.generation));
    }

    ////////////////////////////////////////

    pub fn get_immortal(self: World, entity: EntityId) bool {
        if (self.valid_entity(entity)) {
            return self.generations.items[entity.index].immortal;
        }
        return false;
    }

    ////////////////////////////////////////

    pub fn set_label(self: *World, entity_id: EntityId, label: String) void {
        self.set_kind(entity_id, self.String, @constCast(@ptrCast(&label)));
    }

    ////////////////////////////////////////

    pub fn get_label(self: World, entity_id: EntityId) ?String {
        if (self.valid_entity(entity_id)) {
            if (self.get(entity_id, String)) |str| {
                return str;
            }
        }
        return null;
    }

    ////////////////////////////////////////

    pub fn destroy(self: *World, entity: EntityId) void {
        if (self.valid_entity(entity) and self.get_immortal(entity) == false) {
            var next_generation = entity.generation + 1;
            if (next_generation == max_generation) {
                next_generation = 0;
            }

            const ed = EntityData{ .index = self.next_deleted, .generation = next_generation, .immortal = false };
            self.generations.items[entity.index] = ed;
            self.next_deleted = entity.index;
            self.num_deleted += 1;
        }
    }

    ////////////////////////////////////////

    pub fn set_kind(self: *World, entity: EntityId, kind: usize, value: [*]const u8) void {
        if (!self.valid_entity(entity)) return;

        if (self.get_type_info(kind)) |ci| {
            ci.set_data(self.alloc, entity.index, value) catch {};
        } else {
            std.debug.print("Cannot set_kind without registered component type", .{});
            return;
        }
    }

    ////////////////////////////////////////

    pub fn set(self: *World, entity: EntityId, comptime value: anytype) void {
        if (!self.valid_entity(entity)) return;

        const T = @TypeOf(value);
        const ci = get_component_info(T);

        if (ci.self == 0) {
            _ = self.register_component(T, null) catch {};
        }

        ci.set(self.alloc, entity.index, value) catch {};
    }

    ////////////////////////////////////////

    pub fn get(self: World, entity: EntityId, comptime T: type) ?T {
        if (!self.valid_entity(entity)) return null;

        const ci = get_component_info(T);

        return ci.get(entity.index);
    }

    ////////////////////////////////////////

    pub fn get_type_info(self: World, erased_ptr: usize) ?*TypeInfo(u8) {
        if (self.components.get(erased_ptr)) |_| {
            return @ptrFromInt(erased_ptr);
        }
        return null;
    }

    ////////////////////////////////////////

    pub fn register_component(self: *World, comptime C: type, maybe_name: ?[]const u8) !usize {
        const ci = get_component_info(C);
        const erased_ptr = @intFromPtr(ci);

        const result = self.components.getOrPut(self.alloc, erased_ptr) catch {
            return erased_ptr;
        };

        if (result.found_existing) {
            if (maybe_name == null) {
                return erased_ptr;
            }
            const this_name = intern(maybe_name.?);
            const existing_name = ci.label;

            if (existing_name != null and !string.eql(existing_name.?, this_name)) {
                ci.label = this_name;
            }
            return erased_ptr;
        }

        var fields: std.ArrayListUnmanaged(ComponentField) = .{};

        switch (@typeInfo(C)) {
            .Struct => |struct_type_info| {
                inline for (struct_type_info.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Struct => {
                            const field_ci = try self.register_component(field.type, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = field_ci,
                                },
                            ) catch unreachable;
                        },
                        .Array => |arr| {
                            const field_ci = try self.register_component(arr.child, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .array_length = arr.len,
                                    .kind = field_ci,
                                },
                            ) catch unreachable;
                        },
                        .Pointer => |ptr| {
                            const field_ci = try self.register_component(ptr.child, null);
                            if (ptr.size == .Slice) {
                                fields.append(
                                    self.alloc,
                                    .{
                                        .name = intern(field.name),
                                        .offset = @bitOffsetOf(C, field.name),
                                        .size = @bitSizeOf(field.type),
                                        .array_length = 0,
                                        .kind = field_ci,
                                    },
                                ) catch unreachable;
                            } else {
                                std.debug.print("Unsupported pointer type {s}\n", .{@typeName(field.type)});
                                return error.CannotRegisterComponent_UnsupportedPointerType;
                            }
                        },
                        .Vector => |vec| {
                            const field_ci = try self.register_component(vec.child, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .array_length = vec.len,
                                    .kind = field_ci,
                                },
                            ) catch unreachable;
                        },
                        .Enum => {
                            const field_ci = try self.register_component(field.type, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = field_ci,
                                },
                            ) catch unreachable;
                        },
                        else => {
                            const field_ci = try self.register_component(field.type, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = field_ci,
                                },
                            ) catch unreachable;
                        },
                    }
                }
            },
            .Enum => |enum_type_info| {
                inline for (enum_type_info.fields) |field| {
                    fields.append(
                        self.alloc,
                        .{
                            .name = intern(field.name),
                            .value = field.value,
                        },
                    ) catch unreachable;
                }
            },
            else => {},
        }

        ci.fields = fields;
        ci.self = erased_ptr;
        if (maybe_name) |name| {
            ci.label = intern(name);
        }

        return erased_ptr;
    }

    ////////////////////////////////////////

    pub fn step(self: World, delta_time: f32) void {
        _ = self;
        _ = delta_time;
    }

    ////////////////////////////////////////

    pub fn serialize(self: World, writer: anytype) !void {
        try writer.writeAll("Serialize {\n");

        try self.serialize_entities(writer);

        try writer.writeAll("}\n");
    }

    ////////////////////////////////////////

    fn serialize_entities(self: World, writer: anytype) !void {
        for (0.., self.generations.items) |index, ed| {
            if (ed.index == @as(EntityIndex, @truncate(index))) {
                const entity = EntityId{
                    .index = ed.index,
                    .generation = ed.generation,
                };

                try writer.writeAll("{\n");
                try serialize_entity_components(self, entity, writer);
                try writer.writeAll("}\n");
            }
        }
    }

    ////////////////////////////////////////

    fn serialize_entity_components(self: World, entity: EntityId, writer: anytype) !void {
        var component_iterator = self.components.iterator();
        while (component_iterator.next()) |com| {
            const void_ci: *TypeInfo(u8) = @ptrFromInt(com.key_ptr.*);
            if (void_ci.get_data(entity.index)) |value| {
                try writer.print("{} {} ", .{ entity, void_ci.name });
                try serialize_value(self, void_ci, value, writer);
                try writer.writeAll("\n");
            }
        }
    }

    ////////////////////////////////////////

    fn serialize_value(self: World, ci: *TypeInfo(u8), value: []const u8, writer: anytype) !void {
        if (ci.self == self.f32) {
            const data: *const f32 = @alignCast(@ptrCast(value.ptr));
            try writer.print("{d:0.6}", .{data.*});
        } else if (ci.self == self.String) {
            const data: *const String = @alignCast(@ptrCast(value.ptr));
            try writer.print("{'}", .{data.*});
        } else if (ci.fields.items.len > 0) {
            try writer.writeAll("{");
            var count: usize = 0;
            for (ci.fields.items) |field| {
                if (count > 0) try writer.writeAll(", ");

                const start_index = field.offset / 8;
                const end_index = start_index + field.size / 8;

                const part = value[start_index..end_index];

                if (self.get_type_info(field.kind)) |field_ci| {
                    try self.serialize_value(field_ci, part, writer);
                } else {
                    try writer.print("{any}", .{part});
                }
                count += 1;
            }
            try writer.writeAll("}");
        } else {
            try writer.print("{any}", .{value});
        }
    }

    ////////////////////////////////////////

    pub fn format(self: World, fmt: []const u8, opt: anytype, writer: anytype) !void {
        _ = fmt;
        _ = opt;
        try writer.writeAll("World");
        try writer.print("\n  Entities {}", .{self.generations.items.len});
        if (self.generations.items.len > 0) {
            for (0.., self.generations.items) |index, ed| {
                if (ed.index == @as(EntityIndex, @truncate(index))) {
                    const e = EntityId{
                        .index = ed.index,
                        .generation = ed.generation,
                    };
                    try writer.print("\n    {}", .{e});
                    if (self.get_label(e)) |label| {
                        try writer.print(" {'}", .{label});
                    }
                    if (ed.immortal) {
                        try writer.writeAll(" (immortal)");
                    }
                }
            }
        }
        try writer.print("\n  Components {}", .{self.components.count()});
        var component_iterator = self.components.iterator();
        while (component_iterator.next()) |com| {
            const ci: *TypeInfo(void) = @ptrFromInt(com.key_ptr.*);
            try writer.print("\n    {}", .{ci.name});
            if (ci.label) |label| {
                try writer.print(" {'}", .{label});
            }
            try writer.print(" {{{} bytes}} {} {}", .{
                ci.size,
                com.value_ptr.*,
                ci.len,
            });
            for (ci.fields.items) |field| {
                try writer.print("\n      .{s}", .{field.name});
                if (field.value) |value| {
                    try writer.print(" = {}", .{value});
                } else {
                    try writer.writeAll(" : ");
                    if (field.array_length) |len| {
                        if (len > 0) {
                            try writer.print("[{}]", .{len});
                        } else {
                            try writer.writeAll("[]");
                        }
                    }
                    if (self.get_type_info(field.kind)) |field_ci| {
                        try writer.print("{}", .{field_ci.name});
                    }
                    try writer.print(" ({}:{})", .{ field.offset, field.size });
                }
            }
            var index_iterator = ci.indexes.iterator();
            while (index_iterator.next()) |item| {
                const ed = self.generations.items[item.key_ptr.*];
                const entity = EntityId{
                    .index = ed.index,
                    .generation = ed.generation,
                };
                try writer.print("\n      {} = {}", .{ entity, item.value_ptr.* });
            }
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
