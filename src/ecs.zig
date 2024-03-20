///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const ecs = @import("zflecs");

pub const version = std.SemanticVersion{ .major = 3, .minor = 2, .patch = 7 };

pub const EntityId = ecs.entity_t;

pub const Iter = ecs.iter_t;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn init(allocator: std.mem.Allocator) World {
    _ = ecs.log_set_level(-1);
    const world = ecs.init(allocator);
    return .{
        .world = world,
    };
}

pub const Phase = enum {
    OnUpdate,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Entity = struct {
    id: ecs.entity_t,
    world: *ecs.world_t,

    ////////////////////////////////////////

    pub fn set_label(self: Entity, name: [:0]const u8) void {
        _ = ecs.set_name(self.world, self.id, name);
    }

    ////////////////////////////////////////

    pub fn add(self: Entity, comptime T: type) void {
        const entity_id = ecs.id(T);
        if (entity_id == 0) {
            std.debug.print("unregistered {s}\n", .{@typeName(T)});
            if (@sizeOf(T) == 0) {
                ecs.TAG(self.world, T);
            } else {
                ecs.COMPONENT(self.world, T);
            }
        }
        ecs.add(self.world, self.id, T);
    }

    ////////////////////////////////////////

    pub fn set(self: Entity, comptime T: type, val: T) void {
        const entity_id = ecs.id(T);
        if (entity_id == 0) {
            std.debug.print("unregistered {s}\n", .{@typeName(T)});
            ecs.COMPONENT(self.world, T);
        }
        _ = ecs.set(self.world, self.id, T, val);
    }

    ////////////////////////////////////////

    pub fn delete(self: Entity) void {
        ecs.delete(self.world, self.id);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const World = struct {
    world: *ecs.world_t = undefined,

    ////////////////////////////////////////

    pub fn deinit(self: *World) void {
        _ = ecs.fini(self.world);
    }

    ////////////////////////////////////////

    pub fn register_component(self: *World, comptime T: type, name: [:0]const u8) void {
        ecs.componentWithOptions(self.world, T, .{ .name = name, .symbol = name });
    }

    ////////////////////////////////////////

    pub fn register_tag(self: *World, comptime T: type, name: [:0]const u8) void {
        ecs.tagWithOptions(self.world, T, .{ .name = name });
    }

    ////////////////////////////////////////

    pub fn new(self: *World) Entity {
        const entity_id = ecs.new_id(self.world);
        return .{
            .id = entity_id,
            .world = self.world,
        };
    }

    ////////////////////////////////////////

    pub const SystemOptions = struct {
        phase: Phase = .OnUpdate,
        interval: f32 = 0,
    };

    pub fn system_callback1(iter: *ecs.iter_t) callconv(.C) void {
        std.debug.print("System Callback0 {}\n", .{iter.count_});
        const func : *const fn (iter: *ecs.iter_t) void = @ptrCast (iter.ctx);
        func (iter);
    }

    pub fn system_callback2(iter: *ecs.iter_t) callconv(.C) void {
        std.debug.print("System Callback1 {}\n", .{iter.count_});
        const func : *const fn (c1: []u8, iter: *ecs.iter_t) void = @ptrCast (iter.ctx);
        const s1 = ecs.field_size (iter, 1);
        var p1 : []u8 = undefined;
        p1.ptr = @ptrCast (ecs.field_w_size (iter, s1, 1).?);
        p1.len = @intCast (iter.count_);
        func (p1, iter);
    }

    pub fn system_callback3(iter: *ecs.iter_t) callconv(.C) void {
        std.debug.print("System Callback2 {}\n", .{iter.count_});
        const func : *const fn (c1: []u8, c2: []u8, iter: *ecs.iter_t) void = @ptrCast (iter.ctx);
        const s1 = ecs.field_size (iter, 1);
        const s2 = ecs.field_size (iter, 2);
        var p1 : []u8 = undefined;
        var p2 : []u8 = undefined;
        p1.ptr = @ptrCast (ecs.field_w_size (iter, s1, 1).?);
        p1.len = @intCast (iter.count_);
        p2.ptr = @ptrCast (ecs.field_w_size (iter, s2, 2).?);
        p2.len = @intCast (iter.count_);
        func (p1, p2, iter);
    }

    pub fn system_callback4(iter: *ecs.iter_t) callconv(.C) void {
        std.debug.print("System Callback3 {}\n", .{iter.count_});
    }

    pub fn system_callback5(iter: *ecs.iter_t) callconv(.C) void {
        std.debug.print("System Callback4 {}\n", .{iter.count_});
    }

    pub fn register_system(
        self: *World,
        name: [*:0]const u8,
        func: anytype,
        options: SystemOptions,
    ) void {
        const ecs_phase = switch (options.phase) {
            .OnUpdate => ecs.OnUpdate,
        };
        var desc = ecs.system_desc_t{
            .interval = options.interval,
            .ctx = @constCast (@ptrCast (&func)),
        };

        const func_type_info = @typeInfo(@TypeOf(func));
        if (func_type_info != .Fn) {
            @compileError("Function expected, found " ++ @typeName(@TypeOf(func)));
        }

        std.debug.print("func is func\n", .{});
        const func_info = func_type_info.Fn;
        std.debug.assert(func_info.is_var_args == false);
        std.debug.assert(func_info.is_generic == false);
        std.debug.assert(func_info.return_type != null);
        std.debug.assert(func_info.return_type == void);
        std.debug.print("params.len = {}\n", .{func_info.params.len});

        switch (func_info.params.len)
        {
            0 => @compileError ("No iter parameter"),
            1 => desc.callback = system_callback1,
            2 => desc.callback = system_callback2,
            3 => desc.callback = system_callback3,
            4 => desc.callback = system_callback4,
            5 => desc.callback = system_callback5,
            else => @compileError("Too many parameters in function - this can be fixed"),
        }

        desc.ctx = @constCast (@ptrCast (&func));

        var has_iter = false;
        var iter_is_last = false;

        inline for (func_info.params, 0..) |param, i| {
            std.debug.print("{}\n", .{param});

            const param_type = param.type.?;
            const param_type_info = @typeInfo(param_type);

            iter_is_last = false;
            if (param_type_info == .Pointer) {
                const pointer = param_type_info.Pointer;

                if (pointer.size == .One and pointer.child == ecs.iter_t) {
                    if (has_iter) {
                        // @compileError ("Function has too many *iter parameters");
                        std.debug.print("too many iter parameters\n", .{});
                    }
                    has_iter = true;
                    iter_is_last = true;
                } else if (pointer.size == .Slice) {
                    desc.query.filter.terms[i].id = ecs.id(pointer.child);
                    desc.query.filter.terms[i].inout = if (pointer.is_const) .In else .InOut;
                }
            } else {
                std.debug.print("invalid parameter type\n", .{});
            }
        }

        if (!has_iter) {
            // @compileError ("Function does not have an *iter parameter");
            std.debug.print("no iter parameters\n", .{});
        }
        if (!iter_is_last) {
            // @compileError ("Function does not have an *iter parameter as the last parameter");
            std.debug.print("not last iter parameters\n", .{});
        }

        std.debug.print("has_iter = {}, iter_is_last = {}\n", .{ has_iter, iter_is_last });
        std.debug.print("CTX {*}\n", .{name});
        ecs.SYSTEM(self.world, name, ecs_phase, &desc);
    }

    ////////////////////////////////////////

    pub fn progress(self: *World, delta_time: f32) void {
        _ = ecs.progress(self.world, delta_time);
    }

    ////////////////////////////////////////

    pub fn serialize(self: World, writer: anytype) !void {
        try writer.print("World {*}\n", .{self.world});
        var filter: ecs.filter_t = .{};
        var filter_desc = ecs.filter_desc_t{
            .storage = &filter,
        };

        filter_desc.terms[0].id = ecs.pair(ecs.ChildOf, ecs.Flecs);
        filter_desc.terms[0].oper = .Not;
        filter_desc.terms[0].src.flags = ecs.Self | ecs.Parent;

        filter_desc.terms[1].id = ecs.Module;
        filter_desc.terms[1].oper = .Not;
        filter_desc.terms[1].src.flags = ecs.Self | ecs.Parent;

        filter_desc.terms[2].id = ecs.Component;
        filter_desc.terms[2].oper = .Not;
        filter_desc.terms[2].src.flags = ecs.Self | ecs.Parent;

        filter_desc.terms[3].id = ecs.System;
        filter_desc.terms[3].oper = .Not;
        filter_desc.terms[3].src.flags = ecs.Self | ecs.Parent;

        _ = try ecs.filter_init(self.world, &filter_desc);

        var iter = ecs.filter_iter(self.world, &filter);
        while (ecs.iter_next(&iter)) {
            const table_type = ecs.table_get_type(iter.table);
            try writer.writeAll("Table ");
            for (0..@intCast(table_type.count)) |i| {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                const id = table_type.array[i];
                if (ecs.id_is_pair(id)) {
                    const first = ecs.pair_first(id);
                    const second = ecs.pair_second(id);
                    try writer.writeAll("(");
                    if (ecs.get_name(self.world, first)) |name| {
                        try writer.print("{s}", .{name});
                    } else {
                        try writer.print("{x:0>8}", .{id});
                    }
                    try writer.writeAll(",");
                    if (ecs.get_name(self.world, second)) |name| {
                        try writer.print("{s}", .{name});
                    } else {
                        try writer.print("{x:0>8}", .{id});
                    }
                    try writer.writeAll(")");
                } else {
                    if (ecs.get_name(self.world, id)) |name| {
                        try writer.print("{s}", .{name});
                    } else {
                        try writer.print("{x:0>8}", .{id});
                    }
                }
            }
            const count: usize = @intCast(ecs.table_column_count(iter.table));
            try writer.writeAll("\n");
            for (0..@intCast(iter.count_)) |i| {
                for (0..count) |j| {
                    const k: usize = @intCast(ecs.table_column_to_type_index(iter.table, @intCast(j)));
                    const id = table_type.array[k];
                    const s = ecs.table_get_column_size(iter.table, @intCast(j));
                    const ptr = ecs.table_get_column(iter.table, @intCast(j), @intCast(i));
                    const data: [*]u8 = @ptrCast(ptr);
                    try writer.print("  {x:0>8} ", .{iter.entities_[i]});
                    if (ecs.id_is_pair(id)) {
                        const first = ecs.pair_first(id);
                        const second = ecs.pair_second(id);
                        try writer.writeAll("(");
                        if (ecs.get_name(self.world, first)) |name| {
                            try writer.print("{s}", .{name});
                        } else {
                            try writer.print("{x:0>8}", .{id});
                        }
                        try writer.writeAll(",");
                        if (ecs.get_name(self.world, second)) |name| {
                            try writer.print("{s}", .{name});
                        } else {
                            try writer.print("{x:0>8}", .{id});
                        }
                        try writer.writeAll(")");
                    } else {
                        if (ecs.get_name(self.world, id)) |name| {
                            try writer.print("{s}", .{name});
                        } else {
                            try writer.print("{x:0>8}", .{id});
                        }
                    }
                    const first = ecs.pair_first(id);
                    if (first == ecs.Identifier) {
                        const ident: *ecs.identifier_t = @alignCast(@ptrCast(data));
                        const str: []u8 = ident.value[0..@intCast(ident.length)];
                        try writer.print("\n      '{'}'", .{std.zig.fmtEscapes(str)});
                    } else if (first == ecs.Description) {
                        const desc: *ecs.description_t = @alignCast(@ptrCast(data));
                        const str: []const u8 = std.mem.span(desc.value);
                        try writer.print("\n      '{'}'", .{std.zig.fmtEscapes(str)});
                    } else if (id == ecs.Component) {
                        const desc: *ecs.component_t = @alignCast(@ptrCast(data));
                        try writer.print("\n      .size = {}, .alignment = {}", .{ desc.size, desc.alignment });
                    } else {
                        for (0..s) |l| {
                            if (l % 16 == 0) {
                                try writer.writeAll("\n     ");
                            } else if (l % 16 == 8) {
                                try writer.writeAll("  ");
                            } else if (l % 8 == 4) {
                                try writer.writeAll(" ");
                            }
                            try writer.print(" {x:0>2}", .{data[l]});
                        }
                    }
                    try writer.writeAll("\n");
                }
            }
        }

        ecs.filter_fini(&filter);
    }

    ////////////////////////////////////////

    pub fn format(self: World, _: anytype, _: anytype, writer: anytype) !void {
        try writer.print("World {*}", .{self.world});
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
