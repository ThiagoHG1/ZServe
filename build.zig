const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.graph.host;
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.link_libc = true;

    const lib = b.addLibrary(.{
        .name = "ZServe",
        .root_module = mod,
    });

    b.installArtifact(lib);

    b.modules.put("ZServe", mod) catch unreachable;
}
