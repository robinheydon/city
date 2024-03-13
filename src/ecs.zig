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
    size: usize = 0,
    alignment: usize = 0,
    hash: TypeHash = 0,
    entity_id: EntityId = .{},

    const TypeHash = u64;

    ////////////////////////////////////////

    inline fn per_type_global_var(comptime T: type) *TypeInfo {
        _ = T;
        return &(struct {
            var ti: TypeInfo = .{};
        }.ti);
    }

    ////////////////////////////////////////

    pub fn from(comptime T: type) *TypeInfo {
        const tip = per_type_global_var(T);
        if (tip.entity_id.index == max_index and tip.entity_id.generation == max_generation) {
            tip.* = TypeInfo{
                .size = @sizeOf(T),
                .alignment = @alignOf(T),
                .hash = @intFromPtr(tip),
                .entity_id = .{},
            };
        }
        return tip;
    }

    ////////////////////////////////////////

    pub fn lessThan(ctx: void, lhs: *const TypeInfo, rhs: *const TypeInfo) bool {
        _ = ctx;
        return lhs.hash < rhs.hash;
    }
};

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
const ComponentArray = std.AutoArrayHashMapUnmanaged(TypeInfo.TypeHash, ComponentInfo);
const EntityLabels = std.AutoArrayHashMapUnmanaged(EntityIndex, String);
const EntityPositions = std.ArrayListUnmanaged(EntityPosition);

////////////////////////////////////////

const EntityPosition = struct {
    archetype: *Archetype,
    index: usize,
};

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
    kind: EntityId = .{},
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

    const empty: ComponentList = .{};

    world.void_archetype = world.add_archetype(empty).?;

    world.null = (try world.register_component(void, null)).id;
    world.bool = (try world.register_component(bool, null)).id;
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
    world.String = (try world.register_component(String, null)).id;
    world.EntityId = (try world.register_component(EntityId, null)).id;

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
        const type_info = TypeInfo.from(T);
        if (self.world.get_label (type_info.entity_id)) |label|
        {
        std.debug.print("get {} {}\n", .{ self.id, label});
        }
        else
        {
        std.debug.print("get {} {}\n", .{ self.id, type_info.entity_id });
        }
        return null;
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

fn hash_component_list(list: ComponentList) ArchetypeHash {
    var hasher = std.hash.Wyhash.init(0);

    for (list.get_slice()) |item| {
        const data = @as ([*]u8, @ptrFromInt (@intFromPtr (&item.index)))[0..3];
        hasher.update(data);
    }

    return hasher.final();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const ComponentList = struct {
    num: usize = 0,
    items: [max_components_per_archetype]EntityId = undefined,

    pub fn add(self: *ComponentList, entity: EntityId) void {
        for (0..self.num) |index| {
            if (self.items[index].index == entity.index) {
                return;
            }
        }
        if (self.num < max_components_per_archetype) {
            self.items[self.num] = entity;
            self.num += 1;
        }
    }

    pub fn remove(self: *ComponentList, entity: EntityId) void {
        for (0..self.num) |index| {
            if (self.items[index].index == entity.index) {
                if (index < self.num - 1)
                {
                    self.items[index] = self.items[self.num-1];
                }
                self.num -= 1;
                return;
            }
        }
    }

    pub fn sort (self: *ComponentList) void {
        std.sort.pdq (EntityId, self.items[0..self.num], {}, EntityId.less_than);
    }

    pub fn get_slice(self: ComponentList) []const EntityId {
        return self.items[0..self.num];
    }

    pub fn format(self: ComponentList, _: anytype, _: anytype, writer: anytype) !void {
        try writer.writeAll("[");
        var count : usize = 0;
        for (self.items[0..self.num]) |item| {
            if (count > 0) {
                try writer.writeAll (",");
            }
            try writer.print("{}", .{item});
            count += 1;
        }
        try writer.writeAll("]");
    }
};

const max_components_per_archetype = 32;

pub const Archetype = struct {
    name: String,
    components: ComponentList = .{},

    pub fn format(self: Archetype, _: anytype, _: anytype, writer: anytype) !void {
        try writer.print("{}", .{self.name});
    }
};

pub const ArchetypeHash = u64;

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

    archetypes: std.AutoArrayHashMapUnmanaged(ArchetypeHash, *Archetype) = .{},
    void_archetype: *Archetype = undefined,
    positions: EntityPositions = .{},

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
        self.positions.deinit(self.alloc);
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
            self.positions.items[index] = .{ .archetype = self.void_archetype, .index = 0 };
            return new_e;
        } else {
            const index = self.generations.items.len;

            if (index < max_index) {
                const ed = EntityData{ .index = @truncate(index), .generation = 0, .immortal = immortal };
                self.generations.append(self.alloc, ed) catch |err| {
                    std.log.err("Cannot extent generations array {}", .{err});
                    return .{ .world = self, .id = .{} };
                };

                const position = EntityPosition{ .archetype = self.void_archetype, .index = 0 };
                self.positions.append(self.alloc, position) catch |err| {
                    std.log.err("Cannot extend entity positions array {}", .{err});
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

            const de = EntityData{ .index = self.next_deleted, .generation = next_generation, .immortal = false };
            self.generations.items[entity.index] = de;
            self.next_deleted = entity.index;
            self.num_deleted += 1;
            _ = self.entity_labels.remove(entity.index);
        }
    }

    ////////////////////////////////////////

    pub fn set(self: *World, entity: EntityId, comptime value: anytype) void {
        if (!self.valid_entity(entity)) {
            return;
        }

        const T = @TypeOf(value);
        const type_info = TypeInfo.from(T);

        const current_position = self.positions.items[entity.index];
        const current_archetype = current_position.archetype;
        const current_components = current_archetype.components;

        var components: ComponentList = current_components;

        components.add(type_info.entity_id);
        components.sort();

        if (self.add_archetype (components)) |new_archetype| {
            self.positions.items[entity.index].archetype = new_archetype;
        }
    }

    ////////////////////////////////////////

    pub fn add_archetype(self: *World, components: ComponentList) ?*Archetype {
        const hash = hash_component_list(components);

        if (self.archetypes.get(hash)) |existing_archetype| {
            return existing_archetype;
        }

        const new_arch = self.alloc.create(Archetype) catch return null;
        errdefer self.alloc.destroy(new_arch);

        var buffer = std.ArrayList(u8).init(self.alloc);
        defer buffer.deinit();
        var writer = buffer.writer();

        writer.writeAll ("[") catch return null;
        var count: usize = 0;
        for (components.items[0..components.num]) |item|
        {
            if (count > 0) {
                writer.writeAll (",") catch return null;
            }
            if (self.get_label(item)) |label| {
                writer.print("{}", .{label}) catch return null;
            } else {
                writer.print ("{}", .{item}) catch return null;
            }
            count += 1;
        }
        writer.writeAll ("]") catch return null;

        new_arch.* = .{
            .name = intern(buffer.items),
            .components = components,
        };

        self.archetypes.put(self.alloc, hash, new_arch) catch return null;
        return new_arch;
    }

    ////////////////////////////////////////

    pub fn register_component(self: *World, comptime C: type, name: ?[]const u8) !Entity {
        var type_info = TypeInfo.from(C);

        var result = self.components.getOrPut(self.alloc, type_info.hash) catch {
            return .{ .world = self };
        };

        if (result.found_existing) {
            if (name == null) {
                return .{ .world = self, .id = result.value_ptr.entity_id };
            }
            const this_name = intern(name.?);
            const existing_name = self.get_label(result.value_ptr.entity_id);

            if (existing_name != null and !string.eql(existing_name.?, this_name)) {
                self.set_label(result.value_ptr.entity_id, this_name);
            }
            return .{ .world = self, .id = result.value_ptr.entity_id };
        }

        const entity = self.create_with_immortal(true);
        const component_name = if (name == null) intern(@typeName(C)) else intern(name.?);

        type_info.entity_id = entity.id;

        result.value_ptr.* = .{
            .name = component_name,
            .type_info = type_info,
            .sparse = false,
            .entity_id = entity.id,
        };

        entity.set_label(component_name);

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

    pub fn step(self: World, delta_time: f32) void {
        _ = self;
        _ = delta_time;
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
                    if (self.entity_labels.get(e.index)) |label| {
                        try writer.print(" {'}", .{label});
                    }
                    if (ed.immortal) {
                        try writer.writeAll(" (immortal)");
                    }
                }
                const position = self.positions.items[index];
                try writer.print(" {}.{}", .{ position.archetype.name, position.index });
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
        try writer.writeAll("\n  Archetypes");
        var archetype_iterator = self.archetypes.iterator();
        var index: usize = 0;
        while (archetype_iterator.next()) |item| : (index += 1) {
            const hash = item.key_ptr.*;
            const name = item.value_ptr.*.name;
            try writer.print("\n    {d}: {x:0>16} {}", .{ index, hash, name });
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
