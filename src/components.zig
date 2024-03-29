///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const math = @import("zmath");
const ecs = @import("ecs.zig");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Velocity = struct {
    dx: f32 = 0,
    dy: f32 = 0,
    dz: f32 = 0,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Rotation = struct {
    x: f32,
    y: f32,
    z: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const BuildingSize = struct {
    x: f32,
    y: f32,
    z: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Owner = struct {
    owner: ecs.EntityId,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Model = packed struct(u32) {
    model_id: u32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const RouteRequest = struct {
    entity: ecs.EntityId,
    source: ecs.EntityId,
    destination: ecs.EntityId,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Node = struct {
    links: std.ArrayListUnmanaged(ecs.EntityId),
    priority: [2]ecs.EntityId,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Link = struct {
    start_node: ecs.EntityId,
    end_node: ecs.EntityId,
    width: f32,
    layout: ecs.EntityId,
    start_control_x: f32,
    start_control_y: f32,
    end_control_x: f32,
    end_control_y: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const LinkLayout = struct {
    width: f32,
    speed_limit: f32,
    number_lanes: u8,
    lanes: [32]Lane,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Lane = struct {
    width: f32,
    kind: LaneKind,
    restrictions: LaneRestriction,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const LaneKind = enum {
    dirt,
    dirt_with_bushes,
    grass,
    grass_with_hedge,
    grass_with_trees,
    pavement,
    pavement_with_trees,
    pavement_with_cycle_parking_0,
    pavement_with_cycle_parking_45,
    pavement_with_cycle_parking_90,
    pavement_with_trees_and_cycle_parking_90,
    cycleway,
    painted_buffer,
    parking_0,
    parking_45,
    parking_90,
    hard_shoulder,
    traffic,
    barrier,
    tram_track,
    rail_track,
    canal,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const LaneRestriction = packed struct(u8) {
    no_general_traffic: bool = false,
    no_autonomous: bool = false,
    no_bus: bool = false,
    no_taxi: bool = false,
    no_hgv: bool = false,
    no_emergency: bool = false,
    no_parking: bool = false,
    no_ped_bike: bool = false,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Route = struct {
    index: usize,
    elapsed: f32,
    source_offset: f32,
    destination_offset: f32,
    nodes: std.ArrayListUnmanaged(Node),
    links: std.ArrayListUnmanaged(Link),
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Person = struct {};
pub const DeadPerson = struct {};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn register(world: *ecs.World) void {
    world.register_component(Route, "Route");
    world.register_component(RouteRequest, "RouteRequest");
    world.register_component(Node, "Node");
    world.register_component(Link, "Link");
    world.register_component(Position, "Position");
    world.register_component(Velocity, "Velocity");
    world.register_component(Rotation, "Rotation");
    world.register_component(BuildingSize, "BuildingSize");
    world.register_component(Model, "Model");
    world.register_component(LinkLayout, "LinkLayout");
    world.register_component(Lane, "Lane");
    world.register_component(LaneKind, "LaneKind");
    world.register_component(LaneRestriction, "LandRestriction");
    world.register_component(Owner, "Owner");

    world.register_tag(DeadPerson, "DeadPerson");
    world.register_tag(Person, "Person");
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
