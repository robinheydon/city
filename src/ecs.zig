///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const ecs = @import("zflecs");

pub const version = std.SemanticVersion{ .major = 3, .minor = 2, .patch = 7 };

pub const EntityId = ecs.entity_t;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn init(allocator: std.mem.Allocator) World {
    _ = allocator;

    const world = ecs.init();
    return .{
        .world = world,
    };
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Entity = struct {
    id: ecs.entity_t,
    world: *ecs.world_t,

    pub fn set_label(self: Entity, name: [:0]const u8) void {
        _ = ecs.set_name(self.world, self.id, name);
    }

    pub fn add(self: Entity, comptime T: type) void {
        const entity_id = ecs.id(T);
        if (entity_id == 0) {
            std.debug.print("unregistered {s}\n", .{@typeName(T)});
            if (@sizeOf(T) == 0) {
                ecs.tag(self.world, T);
            } else {
                ecs.component(self.world, T);
            }
        }
        ecs.add(self.world, self.id, T);
    }

    pub fn set(self: Entity, comptime T: type, val: T) void {
        const entity_id = ecs.id(T);
        if (entity_id == 0) {
            std.debug.print("unregistered {s}\n", .{@typeName(T)});
            ecs.component(self.world, T);
        }
        _ = ecs.set(self.world, self.id, T, val);
    }

    pub fn delete(self: Entity) void {
        ecs.delete(self.world, self.id);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const World = struct {
    world: *ecs.world_t = undefined,

    pub fn deinit (self: *World) void
    {
        _ = ecs.fini (self.world);
    }

    pub fn register_component(self: *World, comptime T: type, name: [:0]const u8) void {
        ecs.component_named(self.world, T, name);
    }

    pub fn register_tag(self: *World, comptime T: type, name: [:0]const u8) void {
        ecs.tag_named(self.world, T, name);
    }

    pub fn new(self: *World) Entity {
        const entity_id = ecs.new_id(self.world);
        return .{
            .id = entity_id,
            .world = self.world,
        };
    }

    pub fn serialize(self: World, writer: anytype) !void {
        try writer.print ("World {*}\n", .{self.world});
        var filter: ecs.filter_t = .{};
        var filter_desc = ecs.filter_desc_t {
            .storage = &filter,
        };

        filter_desc.terms[0].id = ecs.pair (ecs.ChildOf, ecs.Flecs);
        filter_desc.terms[0].oper = .Not;
        filter_desc.terms[0].src.flags = ecs.Self | ecs.Parent;

        filter_desc.terms[1].id = ecs.Module;
        filter_desc.terms[1].oper = .Not;
        filter_desc.terms[1].src.flags = ecs.Self | ecs.Parent;

        _ = try ecs.filter_init (self.world, &filter_desc);

        var iter = ecs.filter_iter (self.world, &filter);
        while (ecs.iter_next (&iter))
        {
            if (ecs.table_str (self.world, iter.table)) |name|
            {
                try writer.print ("Table {s}", .{name});
            }
            else
            {
                try writer.print ("Table", .{});
            }
            try writer.print (" {}", .{iter.count_});
            try writer.writeAll ("\n");
            for (0..@intCast (iter.count_)) |i|
            {
                try writer.print ("  {x:0>8}", .{iter.entities_[i]});
                try writer.writeAll ("\n");
            }
        }

        ecs.filter_fini(&filter);
    }

    pub fn format(self: World, _: anytype, _: anytype, writer: anytype) !void {
        try writer.print("World {*}", .{self.world});
        const buf = ecs.world_to_json(self.world, .{});
        try writer.print("\n{s}", .{buf});
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
