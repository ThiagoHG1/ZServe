const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.graph.host;

    const mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "ZServe",
        .root_module = mod,
    });

    b.installArtifact(lib);

    // ISSO AQUI É O IMPORTANTE
    b.modules.put("ZServe", mod) catch unreachable;
}
