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

const TypeInfo = struct {
    name: []const u8,
    short_name: []const u8,
    size: usize = 0,
    algn: usize = 0,
    hash: TypeHash,

    const TypeHash = u64;

    inline fn per_type_global_var(comptime T: type) *TypeInfo {
        _ = T;
        return &(struct {
            var ti: TypeInfo = undefined;
        }.ti);
    }

    pub fn from(comptime T: type) *const TypeInfo {
        const tip = per_type_global_var(T);
        const name = @typeName(T);
        const last_dot = std.mem.lastIndexOfScalar(u8, name, '.');
        const short_name = if (last_dot) |index| name[index + 1 ..] else name;

        tip.* = TypeInfo{
            .short_name = short_name,
            .name = name,
            .size = @sizeOf(T),
            .algn = @alignOf(T),
            .hash = @intFromPtr(tip),
        };

        return tip;
    }

    pub fn lessThan(ctx: void, lhs: *const TypeInfo, rhs: *const TypeInfo) bool {
        _ = ctx;
        return lhs.hash < rhs.hash;
    }

    pub fn format(self: TypeInfo, fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}", .{self.name});
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

test "TypeInfo" {
    const AType = struct {
        x: u32,
        y: u32,
    };
    const BType = struct { x: u16 };
    const CType = AType;

    const ap = TypeInfo.from(AType);
    const bp = TypeInfo.from(BType);
    const cp = TypeInfo.from(CType);
    try std.testing.expect(ap != bp);
    try std.testing.expect(ap == cp);

    try std.testing.expectEqual(TypeInfo.from(AType), TypeInfo.from(AType));
    try std.testing.expectEqual(TypeInfo.from(AType), TypeInfo.from(CType));
    try std.testing.expect(TypeInfo.from(AType) != TypeInfo.from(BType));
    try std.testing.expect(TypeInfo.from(CType) != TypeInfo.from(BType));
    try std.testing.expectFmt("TypeInfo(AType:8:4)", "{}", .{TypeInfo.from(AType)});
    try std.testing.expectFmt("TypeInfo(BType:2:2)", "{}", .{TypeInfo.from(BType)});
    try std.testing.expectFmt("TypeInfo(AType:8:4)", "{}", .{TypeInfo.from(CType)});
    try std.testing.expectEqual(@as(usize, 8), TypeInfo.from(AType).size);
    try std.testing.expectEqual(@as(usize, 4), TypeInfo.from(AType).algn);
    try std.testing.expectEqual(@as(usize, 2), TypeInfo.from(BType).size);
    try std.testing.expectEqual(@as(usize, 2), TypeInfo.from(BType).algn);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const EntityId = packed struct(u32) {
    index: EntityIndex,
    generation: EntityGeneration,

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

const null_entity_id = EntityId{ .index = max_index, .generation = max_generation };

////////////////////////////////////////

const max_index = std.math.maxInt(EntityIndex);
const max_generation = std.math.maxInt(EntityGeneration);
const GenerationArray = std.ArrayListUnmanaged(EntityData);
const ComponentArray = std.AutoArrayHashMapUnmanaged(TypeInfo.TypeHash, ComponentInfo);
const EntityLabels = std.AutoArrayHashMapUnmanaged(EntityIndex, String);

////////////////////////////////////////

const EntityData = packed struct {
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
    kind: EntityId = null_entity_id,
    value: ?u64 = null,
};

////////////////////////////////////////

const ComponentInfo = struct {
    name: String,
    type_info: *const TypeInfo,
    entity_id: EntityId,
    sparse: bool,
    fields: std.ArrayListUnmanaged(ComponentField) = .{},
};

////////////////////////////////////////

pub fn init(allocator: std.mem.Allocator) !World {
    var world = World{
        .alloc = allocator,
        .next_deleted = max_index,
    };

    try string.init(allocator);

    world.null = (try world.register_component(void)).id;
    world.bool = (try world.register_component(bool)).id;
    world.u8 = (try world.register_component(u8)).id;
    world.u16 = (try world.register_component(u16)).id;
    world.u24 = (try world.register_component(u24)).id;
    world.u32 = (try world.register_component(u32)).id;
    world.u48 = (try world.register_component(u48)).id;
    world.u64 = (try world.register_component(u64)).id;
    world.i8 = (try world.register_component(i8)).id;
    world.i16 = (try world.register_component(i16)).id;
    world.i24 = (try world.register_component(i24)).id;
    world.i32 = (try world.register_component(i32)).id;
    world.i48 = (try world.register_component(i48)).id;
    world.i64 = (try world.register_component(i64)).id;
    world.f32 = (try world.register_component(f32)).id;
    world.f64 = (try world.register_component(f64)).id;
    world.usize = (try world.register_component(usize)).id;
    world.String = (try world.register_component(String)).id;
    world.EntityId = (try world.register_component(EntityId)).id;

    return world;
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Entity = struct {
    world: *World,
    id: EntityId,

    pub fn set_label(self: Entity, label: String) !void {
        try self.world.entity_labels.put(self.world.alloc, self.id.index, label);
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
    components: ComponentArray = .{},
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
                    std.log.err("Cannot create entity {}", .{err});
                    return .{ .world = self, .id = null_entity_id };
                };
                return .{
                    .world = self,
                    .id = .{ .index = ed.index, .generation = ed.generation },
                };
            } else {
                return .{ .world = self, .id = null_entity_id };
            }
        }
    }

    ////////////////////////////////////////

    pub fn create(self: *World) Entity {
        return self.create_with_immortal(false);
    }

    ////////////////////////////////////////

    pub fn valid_entity(self: World, e: Entity) bool {
        return ((e.index != max_index) and
            (e.generation != max_generation) and
            (e.index < self.generations.items.len) and
            (self.generations.items[e.index].generation == e.generation));
    }

    ////////////////////////////////////////

    pub fn get_immortal(self: World, e: Entity) bool {
        return self.generations.items[e.index].immortal;
    }

    ////////////////////////////////////////

    pub fn destroy(self: *World, e: Entity) void {
        if (self.valid_entity(e) and self.get_immortal(e) == false) {
            var next_generation = e.generation + 1;
            if (next_generation == max_generation) {
                next_generation = 0;
            }

            const de = EntityData{ .index = self.next_deleted, .generation = next_generation, .immortal = false };
            self.generations.items[e.index] = de;
            self.next_deleted = e.index;
            self.num_deleted += 1;
        }
    }

    ////////////////////////////////////////

    pub fn register_component(self: *World, comptime C: type) !Entity {
        const type_info = TypeInfo.from(C);

        var result = self.components.getOrPut(self.alloc, type_info.hash) catch {
            return .{ .world = self, .id = null_entity_id };
        };

        if (result.found_existing) {
            return .{ .world = self, .id = result.value_ptr.entity_id };
        }

        const entity = self.create_with_immortal(true);
        const name = try intern(@typeName(C));

        result.value_ptr.* = .{
            .name = name,
            .type_info = type_info,
            .sparse = false,
            .entity_id = entity.id,
        };

        try entity.set_label(name);

        var fields: std.ArrayListUnmanaged(ComponentField) = .{};

        switch (@typeInfo(C)) {
            .Struct => |struct_type_info| {
                inline for (struct_type_info.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Struct => {
                            const ent = try self.register_component(field.type);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = try intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        .Array => |arr| {
                            const ent = try self.register_component(arr.child);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = try intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .array_length = arr.len,
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        .Pointer => |ptr| {
                            const ent = try self.register_component(ptr.child);
                            if (ptr.size == .Slice) {
                                fields.append(
                                    self.alloc,
                                    .{
                                        .name = try intern(field.name),
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
                            const ent = try self.register_component(vec.child);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = try intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .array_length = vec.len,
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        .Enum => {
                            const ent = try self.register_component(field.type);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = try intern(field.name),
                                    .offset = @bitOffsetOf(C, field.name),
                                    .size = @bitSizeOf(field.type),
                                    .kind = ent.id,
                                },
                            ) catch unreachable;
                        },
                        else => {
                            const ent = try self.register_component(field.type);
                            fields.append(
                                self.alloc,
                                .{
                                    .name = try intern(field.name),
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
                            .name = try intern(field.name),
                            .value = field.value,
                        },
                    ) catch unreachable;
                }
            },
            else => {},
        }

        result = self.components.getOrPut(self.alloc, type_info.hash) catch {
            return entity;
        };

        result.value_ptr.fields = fields;

        return entity;
    }

    ////////////////////////////////////////

    pub fn set_sparse_component(self: World, comptime C: type) void {
        const type_info = TypeInfo.from(C);

        if (self.components.getPtr(type_info.hash)) |component| {
            component.sparse = true;
        }
    }

    ////////////////////////////////////////

    pub fn format(self: World, fmt: []const u8, opt: anytype, writer: anytype) !void {
        _ = fmt;
        _ = opt;
        try writer.writeAll("World");
        if (self.generations.items.len > 0) {
            try writer.writeAll("\n  Entities");
            for (0.., self.generations.items) |index, ed| {
                if (ed.index == @as(EntityIndex, @truncate(index))) {
                    const e = EntityId{
                        .index = ed.index,
                        .generation = ed.generation,
                    };
                    try writer.print("\n    {}", .{e});
                    if (ed.immortal)
                        try writer.writeAll("*");
                    if (self.entity_labels.get(e.index)) |label| {
                        try writer.print(" {}", .{label});
                    }
                }
            }
        }
        var component_iterator = self.components.iterator();
        var need_header = true;
        while (component_iterator.next()) |entry| {
            if (need_header) {
                try writer.writeAll("\n  Components");
                need_header = false;
            }
            const comp = entry.value_ptr;
            try writer.print("\n    {}", .{comp.entity_id});
            if (self.entity_labels.get(comp.entity_id.index)) |label| {
                try writer.print(" {'}", .{label});
            } else {
                try writer.print(" {}", .{comp.type_info});
            }
            try writer.print(" ({})", .{comp.type_info.size});
            if (comp.sparse) {
                try writer.writeAll(" (sparse)");
            }

            for (comp.fields.items) |field| {
                try writer.print("\n      .{s} : ", .{field.name});
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
                if (field.value) |value| {
                    try writer.print(" = {}", .{value});
                } else {
                    try writer.print(" ({}:{})", .{ field.offset, field.size });
                }
            }
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// test "World entity sizes" {
//     const Small_World = SmallECS();
//     const Medium_World = MediumECS();
//     const Large_World = LargeECS();
//     const Custom_World = ECS(u10, u6);
//
//     var small_world = Small_World.init(std.testing.allocator);
//     var medium_world = Medium_World.init(std.testing.allocator);
//     var large_world = Large_World.init(std.testing.allocator);
//     var custom_world = Custom_World.init(std.testing.allocator);
//
//     try std.testing.expectEqual(2, @sizeOf(Small_World.Entity));
//     try std.testing.expectEqual(4, @sizeOf(Medium_World.Entity));
//     try std.testing.expectEqual(6, @sizeOf(Large_World.Entity));
//     try std.testing.expectEqual(2, @sizeOf(Custom_World.Entity));
//
//     small_world.deinit();
//     medium_world.deinit();
//     large_world.deinit();
//     custom_world.deinit();
// }

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// test "Entity creation" {
//     var world = SmallECS().init(std.testing.allocator);
//
//     const e0 = world.create();
//     const e1 = world.create();
//     const e2 = world.create();
//     const e3 = world.create();
//     const e4 = world.create();
//     const e5 = world.create();
//
//     try std.testing.expectFmt("E(0:0)", "{}", .{e0});
//     try std.testing.expectFmt("E(0:1)", "{}", .{e1});
//     try std.testing.expectFmt("E(0:2)", "{}", .{e2});
//     try std.testing.expectFmt("E(0:3)", "{}", .{e3});
//     try std.testing.expectFmt("E(0:4)", "{}", .{e4});
//     try std.testing.expectFmt("E(0:5)", "{}", .{e5});
//
//     world.destroy(e2);
//     world.destroy(e4);
//
//     const e6 = world.create();
//     const e7 = world.create();
//
//     try std.testing.expectFmt("E(1:4)", "{}", .{e6});
//     try std.testing.expectFmt("E(1:2)", "{}", .{e7});
//
//     world.destroy(e3);
//     world.destroy(e6);
//
//     const e8 = world.create();
//
//     try std.testing.expectFmt("E(2:4)", "{}", .{e8});
//
//     try std.testing.expectFmt(
//         \\World
//         \\  Entities
//         \\    E(0:0)
//         \\    E(0:1)
//         \\    E(1:2)
//         \\    E(2:4)
//         \\    E(0:5)
//     , "{}", .{world});
//
//     world.deinit();
// }

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// test "Too many entities" {
//     var world = ECS(u3, u8).init(std.testing.allocator);
//
//     const e0 = world.create();
//     const e1 = world.create();
//     const e2 = world.create();
//     const e3 = world.create();
//     const e4 = world.create();
//     const e5 = world.create();
//     const e6 = world.create();
//     const e7 = world.create();
//     const e8 = world.create();
//
//     try std.testing.expectFmt("E(0:0)", "{}", .{e0});
//     try std.testing.expectFmt("E(0:1)", "{}", .{e1});
//     try std.testing.expectFmt("E(0:2)", "{}", .{e2});
//     try std.testing.expectFmt("E(0:3)", "{}", .{e3});
//     try std.testing.expectFmt("E(0:4)", "{}", .{e4});
//     try std.testing.expectFmt("E(0:5)", "{}", .{e5});
//     try std.testing.expectFmt("E(0:6)", "{}", .{e6});
//     try std.testing.expectFmt("E(null)", "{}", .{e7});
//     try std.testing.expectFmt("E(null)", "{}", .{e8});
//
//     try std.testing.expectFmt(
//         \\World
//         \\  Entities
//         \\    E(0:0)
//         \\    E(0:1)
//         \\    E(0:2)
//         \\    E(0:3)
//         \\    E(0:4)
//         \\    E(0:5)
//         \\    E(0:6)
//     , "{}", .{world});
//
//     world.destroy(e3);
//     world.destroy(e2);
//     world.destroy(e5);
//     world.destroy(e6);
//
//     try std.testing.expectFmt(
//         \\World
//         \\  Entities
//         \\    E(0:0)
//         \\    E(0:1)
//         \\    E(0:4)
//     , "{}", .{world});
//
//     const e9 = world.create();
//     const e10 = world.create();
//     const e11 = world.create();
//     const e12 = world.create();
//     const e13 = world.create();
//
//     try std.testing.expectFmt("E(1:6)", "{}", .{e9});
//     try std.testing.expectFmt("E(1:5)", "{}", .{e10});
//     try std.testing.expectFmt("E(1:2)", "{}", .{e11});
//     try std.testing.expectFmt("E(1:3)", "{}", .{e12});
//     try std.testing.expectFmt("E(null)", "{}", .{e13});
//
//     try std.testing.expectFmt(
//         \\World
//         \\  Entities
//         \\    E(0:0)
//         \\    E(0:1)
//         \\    E(1:2)
//         \\    E(1:3)
//         \\    E(0:4)
//         \\    E(1:5)
//         \\    E(1:6)
//     , "{}", .{world});
//
//     try std.testing.expectEqual(@sizeOf(@TypeOf(world.generations.items[0])) * world.generations.capacity, 2 * 8);
//
//     world.deinit();
// }

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// test "valid entity tests" {
//     const World = ECS(u3, u8);
//     var world = World.init(std.testing.allocator);
//
//     const e0 = world.create();
//     const e1 = world.create();
//     const e2 = world.create();
//     const e3 = world.create();
//
//     try std.testing.expectFmt("E(0:0) true", "{} {}", .{ e0, world.valid_entity(e0) });
//     try std.testing.expectFmt("E(0:1) true", "{} {}", .{ e1, world.valid_entity(e1) });
//     try std.testing.expectFmt("E(0:2) true", "{} {}", .{ e2, world.valid_entity(e2) });
//     try std.testing.expectFmt("E(0:3) true", "{} {}", .{ e3, world.valid_entity(e3) });
//
//     world.destroy(e2);
//
//     try std.testing.expectFmt("E(0:0) true", "{} {}", .{ e0, world.valid_entity(e0) });
//     try std.testing.expectFmt("E(0:2) false", "{} {}", .{ e2, world.valid_entity(e2) });
//
//     const e4 = world.create();
//
//     try std.testing.expectFmt("E(0:2) false", "{} {}", .{ e2, world.valid_entity(e2) });
//     try std.testing.expectFmt("E(1:2) true", "{} {}", .{ e4, world.valid_entity(e4) });
//
//     const e5 = World.Entity{ .index = 7, .generation = 0 };
//     const e6 = World.Entity{ .index = 0, .generation = 255 };
//
//     try std.testing.expectFmt("E(0:7) false", "{} {}", .{ e5, world.valid_entity(e5) });
//     try std.testing.expectFmt("E(ff:0) false", "{} {}", .{ e6, world.valid_entity(e6) });
//
//     try std.testing.expectFmt(
//         \\World
//         \\  Entities
//         \\    E(0:0)
//         \\    E(0:1)
//         \\    E(1:2)
//         \\    E(0:3)
//     , "{}", .{world});
//
//     world.deinit();
// }

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// test "simple components" {
//     const Position = struct { x: f32, y: f32 };
//     const Velocity = struct { dx: f32, dy: f32 };
//     const Player = struct {};
//
//     var world = ECS(u8, u8).init(std.testing.allocator);
//
//     const c0 = world.register_component(Position, .{});
//     const e0 = world.create();
//     const e1 = world.create();
//     const c1 = world.register_component(Velocity, .{});
//     const c2 = world.register_component(Position, .{});
//     const c3 = world.register_component(Player, .{});
//     const e2 = world.create();
//     const e3 = world.create();
//
//     try std.testing.expectFmt("E(0:0)", "{}", .{c0});
//     try std.testing.expectFmt("E(0:1)", "{}", .{e0});
//     try std.testing.expectFmt("E(0:2)", "{}", .{e1});
//     try std.testing.expectFmt("E(0:3)", "{}", .{c1});
//     try std.testing.expectFmt("E(0:0)", "{}", .{c2});
//     try std.testing.expectFmt("E(0:4)", "{}", .{c3});
//     try std.testing.expectFmt("E(0:5)", "{}", .{e2});
//     try std.testing.expectFmt("E(0:6)", "{}", .{e3});
//
//     world.destroy(c0);
//     world.destroy(e0);
//
//     try std.testing.expectFmt(
//         \\World
//         \\  Entities
//         \\    E(0:0)*
//         \\    E(0:2)
//         \\    E(0:3)*
//         \\    E(0:4)*
//         \\    E(0:5)
//         \\    E(0:6)
//         \\  Components
//         \\    E(0:0) TypeInfo(Position:8:4)
//         \\    E(0:3) TypeInfo(Velocity:8:4)
//         \\    E(0:4) TypeInfo(Player:0:0)
//     , "{}", .{world});
//
//     world.deinit();
// }

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
