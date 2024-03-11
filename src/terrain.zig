///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const root = @import("root");
const glfw = @import("zglfw");
const gui = @import("zgui");
const opengl = @import("zopengl");
const gl = opengl.bindings;
const math = @import("zmath");
const tracy = @import("ztracy");
const stbi = @import("zstbi");

const fonts = @import("fonts.zig");
const gfx = @import("gfx.zig");
const random = @import("random.zig");
const rand = random.rand;

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const max_map_x = 64 * 1024;
pub const max_map_y = 64 * 1024;

pub const cell_size = 8;

pub const max_tris = 1_000_000;
pub const max_vertex_capacity = 3 * max_tris; // six points per quad: three per tri
pub const max_index_capacity = 3 * max_tris; // six indexes per quad: three per tri

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn init() !void {
    for (0..2) |index| {
        var mesh = try gfx.Mesh(gfx.TerrainVertex).init(
            root.state.allocator,
            .triangles,
        );

        try mesh.set_capacity(max_vertex_capacity, max_index_capacity);

        root.state.terrain_mesh[index] = mesh;
    }

    request_generation();

    root.state.terrain_thread = try std.Thread.spawn(.{}, terrain_thread, .{});
    try root.state.terrain_thread.setName("terrain");
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn deinit() void {
    for (0..2) |index| {
        if (root.state.terrain_mesh[index]) |*grid| {
            grid.deinit();
        }
    }
    root.state.terrain_thread.join();
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn terrain_thread() void {
    var last_terrain_detail: f32 = 0;
    var last_camera_position_x: f32 = 0;
    var last_camera_position_y: f32 = 0;
    var last_camera_target_x: f32 = 0;
    var last_camera_target_y: f32 = 0;
    var last_user_terrain_detail: f32 = 0;
    var last_sea_level: f32 = 0;
    var idle_count: usize = 0;

    while (root.state.running) {
        if (root.state.terrain_generation_requested) {
            var dirty = false;
            if (last_terrain_detail != root.state.terrain_detail) {
                last_terrain_detail = root.state.terrain_detail;
                dirty = true;
            }
            if (last_camera_position_x != root.state.main_camera.position[0]) {
                last_camera_position_x = root.state.main_camera.position[0];
                dirty = true;
            }
            if (last_camera_position_y != root.state.main_camera.position[1]) {
                last_camera_position_y = root.state.main_camera.position[1];
                dirty = true;
            }
            if (last_camera_target_x != root.state.main_camera.target[0]) {
                last_camera_target_x = root.state.main_camera.target[0];
                dirty = true;
            }
            if (last_camera_target_y != root.state.main_camera.target[1]) {
                last_camera_target_y = root.state.main_camera.target[1];
                dirty = true;
            }
            if (last_user_terrain_detail != root.state.user_terrain_detail) {
                last_user_terrain_detail = root.state.user_terrain_detail;
                dirty = true;
            }
            if (last_sea_level != root.state.sea_level) {
                last_sea_level = root.state.sea_level;
                dirty = true;
            }

            if (dirty) {
                create_terrain_mesh() catch {};
                idle_count = 0;
            } else {
                idle_count += 1;
            }
        }

        if (idle_count < 100) {
            std.time.sleep(1 * std.time.ns_per_ms);
        } else {
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn request_generation() void {
    root.state.terrain_generation_requested = true;
    if (root.state.terrain_mesh[root.state.terrain_frame_index +% 1]) |*mesh| {
        mesh.reset() catch {};
        _ = mesh.get_vbo_memory();
        _ = mesh.get_ebo_memory();
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_terrain_mesh() !void {
    const zone = tracy.ZoneNC(@src(), "create_terrain_mesh", 0x00_ff_00_00);
    defer zone.End();

    const index = root.state.terrain_frame_index +% 1;

    if (root.state.terrain_mesh[index]) |*mesh| {
        const max_lod = 7;
        const grid_size: f32 = @floatFromInt(16 << max_lod);

        const lod_size: i32 = @intFromFloat(64 * 1024 / grid_size);

        var grid_lod: [lod_size][lod_size]i8 = undefined;

        for (0..8) |_| {
            for (0..lod_size) |iy| {
                for (0..lod_size) |ix| {
                    grid_lod[iy][ix] = 0;
                }
            }

            const ax: f32 = std.math.clamp(root.state.main_camera.position[0], 0, max_map_x);
            const ay: f32 = std.math.clamp(root.state.main_camera.position[1], 0, max_map_y);
            const az: f32 = root.state.main_camera.position[2];

            const bx: f32 = std.math.clamp(root.state.main_camera.target[0], 0, max_map_x);
            const by: f32 = std.math.clamp(root.state.main_camera.target[1], 0, max_map_y);

            for (0..lod_size) |iy| {
                for (0..lod_size) |ix| {
                    var distance: f32 = @max(max_map_x, max_map_y);
                    for (0..3) |gy| {
                        for (0..3) |gx| {
                            const x_offset = @as(f32, @floatFromInt(gx)) * grid_size / 2;
                            const y_offset = @as(f32, @floatFromInt(gy)) * grid_size / 2;
                            const cx = @as(f32, @floatFromInt(ix)) * grid_size + x_offset;
                            const cy = @as(f32, @floatFromInt(iy)) * grid_size + y_offset;

                            const dx = (ax + bx) / 2 - cx;
                            const dy = (ay + by) / 2 - cy;

                            distance = @sqrt(dx * dx + dy * dy + az * az);
                        }
                    }

                    var test_grid_size: f32 = 16;
                    var lod: i8 = max_lod;
                    if (root.state.user_terrain_detail <= 0.25) {
                        lod -= 2;
                    } else if (root.state.user_terrain_detail <= 0.5) {
                        lod -= 1;
                    }
                    while (test_grid_size <= grid_size) : (test_grid_size *= 2) {
                        if (distance > 32 * 1024 or distance > 96 * 1024 * root.state.user_terrain_detail) {
                            grid_lod[iy][ix] = -1;
                            break;
                        } else if (distance < test_grid_size * root.state.terrain_detail) {
                            grid_lod[iy][ix] = lod;
                            break;
                        }

                        lod -= 1;
                    }
                }
            }

            if (true) {
                for (0..lod_size) |iy| {
                    for (0..lod_size) |ix| {
                        const lod = grid_lod[iy][ix] - 1;
                        if (iy < lod_size - 1 and lod >= grid_lod[iy + 1][ix]) {
                            grid_lod[iy + 1][ix] = lod;
                        }
                        if (ix < lod_size - 1 and lod >= grid_lod[iy][ix + 1]) {
                            grid_lod[iy][ix + 1] = lod;
                        }
                    }
                }

                for (0..lod_size) |iiy| {
                    for (0..lod_size) |iix| {
                        const ix = lod_size - 1 - iix;
                        const iy = lod_size - 1 - iiy;

                        const lod = grid_lod[iy][ix] - 1;
                        if (iy > 0 and lod >= grid_lod[iy - 1][ix]) {
                            grid_lod[iy - 1][ix] = lod;
                        }
                        if (ix > 0 and lod >= grid_lod[iy][ix - 1]) {
                            grid_lod[iy][ix - 1] = lod;
                        }
                    }
                }
            }

            var count_tris: usize = 0;
            for (0..lod_size) |iy| {
                for (0..lod_size) |ix| {
                    if (grid_lod[iy][ix] >= 0) {
                        count_tris += @as(usize, 2) << @intCast(grid_lod[iy][ix] * 2);
                    }
                }
            }

            const tris: f32 = @floatFromInt(count_tris);

            const ratio = tris / (root.state.user_terrain_detail * root.state.target_terrain_tris);
            const full_ratio = tris / root.state.target_terrain_tris;

            if (full_ratio > 0.95) {
                root.state.terrain_detail = root.state.terrain_detail / 2;
            } else if (ratio < 0.75 or ratio > 1) {
                root.state.terrain_detail = root.state.terrain_detail / (ratio + 0.2);
            } else {
                break;
            }

            root.state.terrain_detail = @max(1, @min(400, root.state.terrain_detail));
            if (root.state.terrain_detail == 1 or root.state.terrain_detail == 400) {
                break;
            }
        }

        var y: f32 = 0;
        while (y < 64 * 1024) : (y += grid_size) {
            const iy: usize = @intFromFloat(y / grid_size);
            var x: f32 = 0;
            while (x < 64 * 1024) : (x += grid_size) {
                const ix: usize = @intFromFloat(x / grid_size);
                const lod = grid_lod[iy][ix];
                if (lod >= 0) {
                    _ = try create_terrain_quad(mesh, x, y, grid_size, lod);
                }
            }
        }

        if (mesh.vbo_memory) |vbo| {
            const len = @min(mesh.vertexes.items.len, mesh.vbo_capacity);
            @memcpy(vbo, mesh.vertexes.items[0..len]);
            mesh.vbo_dirty = false;
        }

        if (mesh.ebo_memory) |ebo| {
            const len = @min(mesh.indexes.items.len, mesh.ebo_capacity);
            @memcpy(ebo, mesh.indexes.items[0..len]);
            mesh.ebo_dirty = false;
        }

        root.state.terrain_generation_requested = false;
        root.state.terrain_generation_ready = true;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_terrain_quad(mesh: *root.TerrainMesh, x: f32, y: f32, s: f32, lod: i8) !bool {
    if (lod > 0) {
        const sp = mesh.savepoint();
        const flat1 = try create_terrain_quad(mesh, x, y, s / 2, lod - 1);
        const flat2 = try create_terrain_quad(mesh, x + s / 2, y, s / 2, lod - 1);
        const flat3 = try create_terrain_quad(mesh, x, y + s / 2, s / 2, lod - 1);
        const flat4 = try create_terrain_quad(mesh, x + s / 2, y + s / 2, s / 2, lod - 1);

        if (flat1 and flat2 and flat3 and flat4) {
            mesh.restore(sp);
            return try create_mesh_quad(mesh, x, y, s);
        }
        return false;
    } else {
        return try create_mesh_quad(mesh, x, y, s);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn create_mesh_quad(mesh: *root.TerrainMesh, x: f32, y: f32, s: f32) !bool {
    const h1 = get_point_elevation(x, y);
    const h2 = get_point_elevation(x + s, y);
    const h3 = get_point_elevation(x, y + s);
    const h4 = get_point_elevation(x + s, y + s);

    const p1 = math.f32x4(x, y, h1, 1);
    const p2 = math.f32x4(x + s, y, h2, 1);
    const p3 = math.f32x4(x, y + s, h3, 1);
    const p4 = math.f32x4(x + s, y + s, h4, 1);
    const p12 = p2 - p1;
    const p13 = p3 - p1;
    const p43 = p3 - p4;
    const p42 = p2 - p4;

    const n1 = math.cross3(p12, p13);
    const n2 = math.cross3(p43, p42);

    const n = math.vecToArr3(math.normalize3(n1 + n2));

    const flat = h1 == h2 and h2 == h3 and h3 == h4;

    if (h1 - h3 > h2 - h4) {
        const v1 = try add_map_vertex(mesh, x, y, h1, n, flat);
        const v2 = try add_map_vertex(mesh, x + s, y, h2, n, flat);
        const v3 = try add_map_vertex(mesh, x, y + s, h3, n, flat);

        const v4 = try add_map_vertex(mesh, x, y + s, h3, n, flat);
        const v5 = try add_map_vertex(mesh, x + s, y, h2, n, flat);
        const v6 = try add_map_vertex(mesh, x + s, y + s, h4, n, flat);

        try mesh.addIndex(v1);
        try mesh.addIndex(v2);
        try mesh.addIndex(v3);

        try mesh.addIndex(v4);
        try mesh.addIndex(v5);
        try mesh.addIndex(v6);
    } else {
        const v1 = try add_map_vertex(mesh, x, y, h1, n, flat);
        const v2 = try add_map_vertex(mesh, x + s, y + s, h4, n, flat);
        const v3 = try add_map_vertex(mesh, x, y + s, h3, n, flat);

        const v4 = try add_map_vertex(mesh, x, y, h1, n, flat);
        const v5 = try add_map_vertex(mesh, x + s, y, h2, n, flat);
        const v6 = try add_map_vertex(mesh, x + s, y + s, h4, n, flat);

        try mesh.addIndex(v1);
        try mesh.addIndex(v2);
        try mesh.addIndex(v3);

        try mesh.addIndex(v4);
        try mesh.addIndex(v5);
        try mesh.addIndex(v6);
    }

    return (h1 == h2 and h2 == h3 and h3 == h4);
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

fn add_map_vertex(mesh: *root.TerrainMesh, x: f32, y: f32, z: f32, normal: [3]f32, flat: bool) !u32 {
    // TODO: change color depending on normal

    const r: f32 = 0.5;
    const g: f32 = 1.0;
    const b: f32 = 0.5;

    if (flat) {
        return try mesh.addVertex(.{
            .position = .{ .x = x, .y = y, .z = z },
            .color = .{ .r = 0, .g = 0, .b = 1 },
            .normal = .{ .x = 0, .y = 0, .z = 1 },
        });
    } else {
        return try mesh.addVertex(.{
            .position = .{ .x = x, .y = y, .z = z },
            .color = .{ .r = r, .g = g, .b = b },
            .normal = .{ .x = normal[0], .y = normal[1], .z = normal[2] },
        });
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn init_height_map() !void {
    var map = try stbi.Image.loadFromFile("media/16mgrid.png", 1);
    defer map.deinit();

    for (0..max_map_x / cell_size + 1) |y| {
        for (0..max_map_y / cell_size + 1) |x| {
            root.state.height_map[y][x] = 0;
        }
    }

    var map_data: []u16 = undefined;
    map_data.ptr = @alignCast(@ptrCast(map.data.ptr));
    map_data.len = map.data.len / 2;

    for (0..max_map_x / cell_size + 1) |y| {
        for (0..max_map_x / cell_size + 1) |x| {
            if (x < map.width and y < map.height) {
                const height: f32 = @as(f32, @floatFromInt(map_data[y * map.width + x])) / 60;
                root.state.height_map[y][x] = height;
            } else {
                root.state.height_map[y][x] = rand(f32) * 30 + 10;
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn get_point_elevation(x: f32, y: f32) f32 {
    const hmx: i32 = @intFromFloat(x / cell_size);
    const hmy: i32 = @intFromFloat(y / cell_size);
    const mx: usize = @max(0, @min(max_map_x / cell_size, hmx));
    const my: usize = @max(0, @min(max_map_y / cell_size, hmy));

    const h = root.state.height_map[my][mx];
    if (h <= root.state.sea_level) {
        return root.state.sea_level + 0.1;
    } else {
        return h;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn get_worst_elevation(x: f32, y: f32) f32 {
    const hmx: i32 = @intFromFloat(x / cell_size);
    const hmy: i32 = @intFromFloat(y / cell_size);
    const mx: usize = @max(0, @min(max_map_x / cell_size - 1, hmx));
    const my: usize = @max(0, @min(max_map_y / cell_size - 1, hmy));

    const h1 = root.state.height_map[my][mx];
    const h2 = root.state.height_map[my][mx + 1];
    const h3 = root.state.height_map[my + 1][mx];
    const h4 = root.state.height_map[my + 1][mx + 1];

    const h = @max(@max(h1, h2), @max(h3, h4));
    if (h <= root.state.sea_level) {
        return root.state.sea_level + 0.1;
    } else {
        return h;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
