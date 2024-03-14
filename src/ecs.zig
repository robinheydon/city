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

fn get_component_info (comptime T: type) *TypeInfo(T)
{
    var tip = &(struct {
        var ti: TypeInfo(T) = .{};
    }.ti);

    if (tip.initialized == false)
    {
        tip.init ();
    }

    return tip;
}

fn TypeInfo (comptime T: type) type
{
    return struct {
        initialized: bool = false,
        size: usize = undefined,
        alignment : usize = undefined,
        name: String = undefined,
        entity_id: EntityId = .{ .index = max_index, .generation = max_generation },
        fields: std.ArrayListUnmanaged(ComponentField) = .{},
        indexes: std.AutoArrayHashMapUnmanaged(EntityIndex,usize) = .{},
        len: usize = 0,
        data: std.ArrayListUnmanaged(u8) = .{},

        const Self = @This();

        pub fn init (self: *Self) void
        {
            self.initialized = true;
            self.size = @sizeOf (T);
            self.alignment = @alignOf (T);
            self.name = intern (@typeName (T));
        }

        pub fn deinit (self: *Self) void
        {
            _ = self;
        }

        fn get_offset (self: Self, index: usize) usize
        {
            return index * self.size;
        }

        fn get_index (self: Self, entity_index: EntityIndex) ?usize
        {
            const value = self.indexes.get (entity_index);
            return value;
        }

        pub fn set (self: *Self, alloc: std.mem.Allocator, entity_index: EntityIndex, value: T) !void
        {
            if (self.get_index (entity_index)) |index|
            {
                const offset = self.get_offset (index);
                const dst = self.data.items[offset..offset+self.size];
                const src = @as ([*]u8, @ptrFromInt (@intFromPtr (&value)))[0..self.size];
                @memcpy (dst, src);
                return;
            }
            const src = @as ([*]u8, @ptrFromInt (@intFromPtr (&value)))[0..self.size];
            const last_len = self.data.items.len;

            try self.data.appendSlice (alloc, src);
            errdefer self.data.items.len = last_len;

            try self.indexes.put (alloc, entity_index, self.len);

            self.len += 1;
        }

        pub fn get (self: Self, entity_index: EntityIndex) ?T
        {
            if (self.get_index (entity_index)) |index|
            {
                const offset = self.get_offset (index);
                const src = self.data.items[offset..offset+self.size];
                var value : T = undefined;
                const dst = @as ([*]u8, @ptrFromInt (@intFromPtr (&value)))[0..self.size];
                @memcpy (dst, src);
                return value;
            }
            return null;
        }

        pub fn getData (self: Self, entity_index: EntityIndex) ?[]const u8
        {
            if (self.get_index (entity_index)) |index|
            {
                const offset = self.get_offset (index);
                const src = self.data.items[offset..offset+self.size];
                var value: []u8 = undefined;
                value = src;
                return value;
            }
            return null;
        }

        pub fn format (self: Self, _:anytype, _:anytype, writer: anytype) !void
        {
            try writer.print ("T({})", .{self.name});
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
const EntityLabels = std.AutoArrayHashMapUnmanaged(EntityIndex, String);

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
    kind: EntityId = .{},
    value: ?u64 = null,
};

////////////////////////////////////////

pub fn init(allocator: std.mem.Allocator) !World {
    var world = World{
        .alloc = allocator,
        .next_deleted = max_index,
    };

    try string.init(allocator);

    world.null = (try world.register_component(void, null)).id;
    world.bool = (try world.register_component(bool, null)).id;
    world.u8 = (try world.register_component(u8, null)).id;
    world.u8 = (try world.register_component(u8, null)).id;
    world.u16 = (try world.register_component(u16, null)).id;
    world.u24 = (try world.register_component(u24, null)).id;
    world.u32 = (try world.register_component(u32, null)).id;
    world.u48 = (try world.register_component(u48, null)).id;
    world.u64 = (try world.register_component(u64, null)).id;
    world.i8 = (try world.register_component(i8, null)).id;
    world.i16 = (try world.register_component(i16, null)).id;
    world.i24 = (try world.register_component(i24, null)).id;
    world.i32 = (try world.register_component(i32, null)).id;
    world.i48 = (try world.register_component(i48, null)).id;
    world.i64 = (try world.register_component(i64, null)).id;
    world.f32 = (try world.register_component(f32, null)).id;
    world.f64 = (try world.register_component(f64, null)).id;
    world.usize = (try world.register_component(usize, null)).id;
    world.String = (try world.register_component(String, "String")).id;
    world.EntityId = (try world.register_component(EntityId, "EntityId")).id;

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
        return self.world.get (self.id, T);
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
    components: std.AutoArrayHashMapUnmanaged (usize, EntityId) = .{},
    entity_labels: EntityLabels = .{},

    null: EntityId = undefined,
    bool: EntityId = undefined,
    u8: EntityId = undefined,
    u16: EntityId = undefined,
    u24: EntityId = undefined,
    u32: EntityId = undefined,
    u48: EntityId = undefined,
    u64: EntityId = undefined,
    i8: EntityId = undefined,
    i16: EntityId = undefined,
    i24: EntityId = undefined,
    i32: EntityId = undefined,
    i48: EntityId = undefined,
    i64: EntityId = undefined,
    f32: EntityId = undefined,
    f64: EntityId = undefined,
    usize: EntityId = undefined,
    String: EntityId = undefined,
    EntityId: EntityId = undefined,

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

    pub fn set_label(self: *World, entity: EntityId, label: String) void {
        self.entity_labels.put(self.alloc, entity.index, label) catch {};
    }

    ////////////////////////////////////////

    pub fn get_label(self: World, entity: EntityId) ?String {
        if (self.valid_entity(entity)) {
            return self.entity_labels.get(entity.index);
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
            _ = self.entity_labels.remove(entity.index);
        }
    }

    ////////////////////////////////////////

    pub fn set(self: *World, entity: EntityId, comptime value: anytype) void {
        if (!self.valid_entity(entity)) return;

        const T = @TypeOf(value);
        const ci = get_component_info (T);

        if (ci.entity_id.index == max_index and ci.entity_id.generation == max_generation)
        {
            _ = self.register_component (T, null) catch {};
        }

        ci.set (self.alloc, entity.index, value) catch {};
    }

    ////////////////////////////////////////

    pub fn get (self: *World, entity: EntityId, comptime T: type) ?T {
        if (!self.valid_entity(entity)) return null;

        const ci = get_component_info (T);

        return ci.get (entity.index);
    }

    ////////////////////////////////////////

    pub fn register_component(self: *World, comptime C: type, maybe_name: ?[]const u8) !Entity {
        const ci = get_component_info (C);
        const erased_ptr = @intFromPtr (ci);

        const result = self.components.getOrPut (self.alloc, erased_ptr) catch {
            return .{ .world = self };
        };

        if (result.found_existing) {
            if (maybe_name == null) {
                return .{ .world = self, .id = result.value_ptr.* };
            }
            const this_name = intern(maybe_name.?);
            const existing_name = self.get_label(result.value_ptr.*);

            if (existing_name != null and !string.eql(existing_name.?, this_name)) {
                self.set_label(result.value_ptr.*, this_name);
            }
            return .{ .world = self, .id = result.value_ptr.* };
        }

        const entity = self.create_with_immortal(true);
        const component_name = if (maybe_name == null) intern(@typeName(C)) else intern(maybe_name.?);

        entity.set_label(component_name);
        result.value_ptr.* = entity.id;

        var fields: std.ArrayListUnmanaged(ComponentField) = .{};

        switch (@typeInfo(C)) {
            .Struct => |struct_type_info| {
                inline for (struct_type_info.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Struct => {
                            const ent = try self.register_component(field.type, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        .Array => |arr| {
                            const ent = try self.register_component(arr.child, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .array_length = arr.len,
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        .Pointer => |ptr| {
                            const ent = try self.register_component(ptr.child, null);
                            if (ptr.size == .Slice) {
                                fields.append(
                                    self.alloc,
                                    .{
                                        .name = intern(field.name),
                                        .offset = @bitOffsetOf(C, field.name),
                                        .size = @bitSizeOf(field.type),
                                        .array_length = 0,
                                        .kind = ent.id,
                                    },
                                ) catch unreachable;
                            } else {
                                std.debug.print("Unsupported pointer type {s}\n", .{@typeName(field.type)});
                                return error.CannotRegisterComponent_UnsupportedPointerType;
                            }
                        },
                        .Vector => |vec| {
                            const ent = try self.register_component(vec.child, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .array_length = vec.len,
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        .Enum => {
                            const ent = try self.register_component(field.type, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        else => {
                            const ent = try self.register_component(field.type, null);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = ent.id,
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

        return .{ .world = self, .id = entity.id };
    }

    ////////////////////////////////////////

    pub fn step(self: World, delta_time: f32) void {
        _ = self;
        _ = delta_time;
    }

    ////////////////////////////////////////

    pub fn serialize (self: World, writer: anytype) !void
    {
        try writer.writeAll ("Serialize {\n");

        try self.serialize_entities (writer);

        try writer.writeAll ("}\n");
    }

    ////////////////////////////////////////

    fn serialize_entities (self: World, writer: anytype) !void
    {
        for (0.., self.generations.items) |index, ed| {
            if (ed.index == @as(EntityIndex, @truncate(index))) {
                const entity = EntityId{
                    .index = ed.index,
                    .generation = ed.generation,
                };
                // try writer.print("Entity: {}", .{entity});
                // if (self.entity_labels.get(entity.index)) |label| {
                    // try writer.print(" {'}", .{label});
                // }
                // if (ed.immortal) {
                    // try writer.writeAll(" (immortal)");
                // }
                // try writer.writeAll("\n");

                try serialize_entity_components (self, entity, writer);
            }
        }
    }

    ////////////////////////////////////////

    fn serialize_entity_components (self: World, entity: EntityId, writer: anytype) !void
    {
        var component_iterator = self.components.iterator ();
        while (component_iterator.next ()) |com|
        {
            const void_ci : *TypeInfo(u8) = @ptrFromInt (com.key_ptr.*);
            if (void_ci.getData (entity.index)) |value|
            {
                try writer.print ("{} {} {} {any}\n", .{entity, void_ci.name, void_ci.size, value});
            }
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
                    if (self.entity_labels.get(e.index)) |label| {
                        try writer.print(" {'}", .{label});
                    }
                    if (ed.immortal) {
                        try writer.writeAll(" (immortal)");
                    }
                }
            }
        }
        try writer.print("\n  Components {}", .{self.components.count ()});
        var component_iterator = self.components.iterator ();
        while (component_iterator.next ()) |com|
        {
            const ci : *TypeInfo(void) = @ptrFromInt (com.key_ptr.*);
            try writer.print ("\n    {} {{{} bytes}} {} {}", .{ci.name, ci.size, com.value_ptr.*, ci.len,});
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
                    if (self.entity_labels.get(field.kind.index)) |label| {
                        try writer.print("{}", .{label});
                    } else {
                        try writer.print("{}", .{field.kind});
                    }
                    try writer.print(" ({}:{})", .{ field.offset, field.size });
                }
            }
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
