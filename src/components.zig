///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const math = @import("zmath");
const ecs = @import("zflecs");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const Rotation = struct {
    x: f32,
    y: f32,
    z: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const BuildingSize = struct {
    x: f32,
    y: f32,
    z: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const Model = struct {
    model_id: u32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const RouteRequest = struct {
    entity: ecs.entity_t,
    source: ecs.entity_t,
    destination: ecs.entity_t,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const Node = struct {
    links: std.ArrayListUnmanaged (ecs.entity_t),
    priority_links: [2]ecs.entity_t,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const Link = struct {
    start_node: ecs.entity_t,
    end_node: ecs.entity_t,
    layout: ecs.entity_t,
    start_control_x: f32,
    start_control_y: f32,
    end_control_x: f32,
    end_control_y: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const LinkLayout = struct {
    width: f32,
    speed_limit: f32,
    lanes: std.ArrayListUnmanaged (LaneType),
    lane_widths: std.ArrayListUnmanaged (LaneType),
    restrictions: std.ArrayListUnmanaged (LaneRestriction),
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const LaneType = enum {
    grass,
    grass_with_trees,
    pavement,
    pavement_with_trees,
    cycleway,
    painted_buffer,
    parking_parallel,
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

const LaneRestriction = packed struct (u8) {
    no_general_traffic : bool = false,
    no_autonomous : bool = false,
    no_bus : bool = false,
    no_taxi : bool = false,
    no_hgv : bool = false,
    no_emergency : bool = false,
    no_parking : bool = false,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const Route = struct {
    index: usize,
    elapsed: f32,
    source_offset: f32,
    destination_offset: f32,
    nodes: std.ArrayListUnmanaged (Node),
    links: std.ArrayListUnmanaged (Link),
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
