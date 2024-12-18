const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const app = OdinCompileStep.create(b, .{
        .name = "app",
        .path = b.path("app"),
        .target = target,
        .optimize = optimize,
        .kind = .exe,
    });
    // app.step.dependOn(&b.addInstallFile(b.path(sdl3FromTarget(target.result)), "SDL3.dll").step);
    app.addCollection("en", b.path("."));
    app.addCollection("external", b.path("external"));

    b.getInstallStep().dependOn(&app.step);

    const runner = app.runStep();
    runner.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(runner);
}

// fn sdl3FromTarget(target: std.Target) []const u8 {
//     switch (target.os.tag) {
//         .windows => switch (target.cpu.arch) {
//             .x86_64 => return "sdl3/lib/x64/SDL3.dll",
//             .x86 => return "sdl3/lib/x86/SDL3.dll",
//             .aarch64 => return "sdl3/lib/arm64/SDL3.dll",
//             else => @panic("Unsupported CPU architecture"),
//         },
//         else => @panic("Unsupported OS"),
//     }
// }

pub const OdinCompileStep = struct {
    step: std.Build.Step,
    name: []const u8,
    path: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    kind: std.Build.Step.Compile.Kind,
    dynamic: bool,
    collections: std.ArrayList(Collection),

    out_path: []const u8 = undefined,

    pub const Collection = struct {
        name: []const u8,
        path: std.Build.LazyPath,
    };

    pub const Options = struct {
        name: []const u8,
        path: std.Build.LazyPath,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        kind: std.Build.Step.Compile.Kind = .exe,
        dynamic: bool = false,
    };

    pub fn create(b: *std.Build, options: Options) *OdinCompileStep {
        const step_name = std.fmt.allocPrint(b.allocator, "odin build {s}", .{options.name}) catch unreachable;
        const compile = b.allocator.create(OdinCompileStep) catch unreachable;

        compile.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = step_name,
                .owner = b,
                .makeFn = make,
            }),
            .name = options.name,
            .path = options.path,
            .target = options.target,
            .optimize = options.optimize,
            .kind = options.kind,
            .dynamic = options.dynamic,
            .collections = std.ArrayList(Collection).init(b.allocator),
        };

        const artifact = std.fmt.allocPrint(b.allocator, "{s}{s}", .{
            b.pathResolve(&.{ b.install_prefix, options.name }),
            extension(compile.target.result, compile.kind, compile.dynamic),
        }) catch unreachable;
        compile.out_path = artifact;

        return compile;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const b = step.owner;
        const compile: *OdinCompileStep = @fieldParentPtr("step", step);

        var args = std.ArrayList([]const u8).init(b.allocator);
        try args.append("odin");
        try args.append("build");
        try args.append(compile.path.getPath2(b, step));

        try b.truncateFile(compile.out_path);

        if (compile.optimize == .Debug) {
            try args.append("-debug");
        }

        const out_arg = try std.fmt.allocPrint(b.allocator, "-out:{s}", .{compile.out_path});
        try args.append(out_arg);

        for (compile.collections.items) |collection| {
            const path = collection.path.getPath2(b, step);
            try args.append(try std.fmt.allocPrint(b.allocator, "-collection:{s}={s}", .{ collection.name, path }));
        }

        const target = try std.fmt.allocPrint(b.allocator, "-target:{s}", .{odinTargetString(b.allocator, compile.target.result)});
        try args.append(target);

        var process = std.process.Child.init(args.items, b.allocator);
        process.cwd = b.pathResolve(&.{"."});
        process.stderr_behavior = .Inherit;
        process.stdout_behavior = .Inherit;
        _ = try process.spawnAndWait();
    }

    pub fn runStep(self: *OdinCompileStep) *std.Build.Step {
        const b = self.step.owner;
        const runner = std.Build.Step.Run.create(self.step.owner, std.fmt.allocPrint(
            self.step.owner.allocator,
            "run {s}",
            .{self.name},
        ) catch unreachable);
        runner.setCwd(b.path(b.install_prefix));
        runner.addArg(self.name);
        return &runner.step;
    }

    pub fn addCollection(self: *OdinCompileStep, name: []const u8, path: std.Build.LazyPath) void {
        self.collections.append(.{ .name = name, .path = path }) catch unreachable;
    }

    fn odinTargetString(allocator: std.mem.Allocator, target: std.Target) []const u8 {
        const arch_string = switch (target.cpu.arch) {
            .wasm32 => return "freestanding_wasm32",
            .x86_64 => "amd64",
            .x86 => "i386",
            .arm => "arm32",
            .aarch64 => "arm64",
            else => @panic("Unsupported CPU architecture"),
        };

        return std.fmt.allocPrint(allocator, "{s}_{s}", .{ osString(target.os.tag), arch_string }) catch unreachable;
    }

    fn osString(os: std.Target.Os.Tag) []const u8 {
        return switch (os) {
            .windows => "windows",
            .linux => "linux",
            .macos => "darwin",
            else => "freestanding",
        };
    }

    fn extension(target: std.Target, kind: std.Build.Step.Compile.Kind, dynamic: bool) []const u8 {
        return switch (target.os.tag) {
            .windows => switch (kind) {
                .exe, .@"test" => ".exe",
                .lib => if (dynamic) ".dll" else ".lib",
                else => "",
            },
            else => "",
        };
    }
};
