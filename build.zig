const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

// FIXME: instead of putting macos homebrew path etc., provide build options to pass them

const BuzzDebugOptions = struct {
    debug: bool,
    stack: bool,
    current_instruction: bool,
    perf: bool,
    stop_on_report: bool,
    placeholders: bool,

    pub fn step(self: BuzzDebugOptions, options: *std.build.OptionsStep) void {
        options.addOption(@TypeOf(self.debug), "debug", self.debug);
        options.addOption(@TypeOf(self.stack), "debug_stack", self.stack);
        options.addOption(@TypeOf(self.current_instruction), "debug_current_instruction", self.current_instruction);
        options.addOption(@TypeOf(self.perf), "show_perf", self.perf);
        options.addOption(@TypeOf(self.stop_on_report), "stop_on_report", self.stop_on_report);
        options.addOption(@TypeOf(self.placeholders), "debug_placeholders", self.placeholders);
    }
};

const BuzzJITOptions = struct {
    off: bool,
    debug: bool,
    prof_threshold: f64 = 0.005,

    pub fn step(self: BuzzJITOptions, options: *std.build.OptionsStep) void {
        options.addOption(@TypeOf(self.debug), "jit_debug", self.debug);
        options.addOption(@TypeOf(self.off), "jit_off", self.off);
        options.addOption(@TypeOf(self.prof_threshold), "jit_prof_threshold", self.prof_threshold);
    }
};

const BuzzGCOptions = struct {
    debug: bool,
    debug_light: bool,
    off: bool,
    initial_gc: usize,
    next_gc_ratio: usize,
    next_full_gc_ratio: usize,

    pub fn step(self: BuzzGCOptions, options: *std.build.OptionsStep) void {
        options.addOption(@TypeOf(self.debug), "gc_debug", self.debug);
        options.addOption(@TypeOf(self.debug_light), "gc_debug_light", self.debug_light);
        options.addOption(@TypeOf(self.off), "gc_off", self.off);
        options.addOption(@TypeOf(self.initial_gc), "initial_gc", self.initial_gc);
        options.addOption(@TypeOf(self.next_gc_ratio), "next_gc_ratio", self.next_gc_ratio);
        options.addOption(@TypeOf(self.next_full_gc_ratio), "next_full_gc_ratio", self.next_full_gc_ratio);
    }
};

const BuzzBuildOptions = struct {
    version: []const u8,
    sha: []const u8,
    use_mimalloc: bool,
    debug: BuzzDebugOptions,
    gc: BuzzGCOptions,
    jit: BuzzJITOptions,

    pub fn step(self: BuzzBuildOptions, b: *std.build.Builder) *std.build.OptionsStep {
        var options = b.addOptions();
        options.addOption(@TypeOf(self.version), "version", self.version);
        options.addOption(@TypeOf(self.sha), "sha", self.sha);
        options.addOption(@TypeOf(self.use_mimalloc), "use_mimalloc", self.use_mimalloc);

        self.debug.step(options);
        self.gc.step(options);
        self.jit.step(options);

        return options;
    }
};

pub fn build(b: *Builder) !void {
    // Check minimum zig version
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse("0.11.0-dev.923+a52dcdd3c") catch return;
    if (current_zig.order(min_zig).compare(.lt)) {
        @panic(b.fmt("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }

    // Make sure dist exists
    std.fs.cwd().makeDir("dist") catch {};
    std.fs.cwd().makeDir("dist/lib") catch {};

    try std.fs.cwd().access("dist/lib", .{});

    var build_options = BuzzBuildOptions{
        // Version is latest tag or empty string
        .version = std.mem.trim(
            u8,
            (std.ChildProcess.exec(.{
                .allocator = std.heap.page_allocator,
                .argv = &.{
                    "git",
                    "describe",
                    "--tags",
                    "--abbrev=0",
                },
                .cwd = b.pathFromRoot("."),
                .expand_arg0 = .expand,
            }) catch {
                std.debug.print("Warning: failed to get git HEAD", .{});
                unreachable;
            }).stdout,
            "\n \t",
        ),
        // Current commit sha
        .sha = std.os.getenv("GIT_SHA") orelse
            std.os.getenv("GITHUB_SHA") orelse std.mem.trim(
            u8,
            (std.ChildProcess.exec(.{
                .allocator = std.heap.page_allocator,
                .argv = &.{
                    "git",
                    "rev-parse",
                    "--short",
                    "HEAD",
                },
                .cwd = b.pathFromRoot("."),
                .expand_arg0 = .expand,
            }) catch {
                std.debug.print("Warning: failed to get git HEAD", .{});
                unreachable;
            }).stdout,
            "\n \t",
        ),
        .use_mimalloc = b.option(
            bool,
            "use_mimalloc",
            "Use mimalloc allocator",
        ) orelse true,
        .debug = .{
            .debug = b.option(
                bool,
                "debug",
                "Show debug information (AST, generated bytecode and more)",
            ) orelse false,
            .stack = b.option(
                bool,
                "debug_stack",
                "Dump stack after each bytecode",
            ) orelse false,
            .current_instruction = b.option(
                bool,
                "debug_current_instruction",
                "Dump stack after each bytecode",
            ) orelse false,
            .perf = b.option(
                bool,
                "show_perf",
                "Show performance information",
            ) orelse false,
            .stop_on_report = b.option(
                bool,
                "stop_on_report",
                "Stop compilation whenever an error is encountered",
            ) orelse false,
            .placeholders = b.option(
                bool,
                "debug_placeholders",
                "Stop compilation whenever an error is encountered",
            ) orelse false,
        },
        .gc = .{
            .debug = b.option(
                bool,
                "gc_debug",
                "Show debug information for the garbage collector",
            ) orelse false,
            .debug_light = b.option(
                bool,
                "gc_debug_light",
                "Show lighter debug information for the garbage collector",
            ) orelse false,
            .off = b.option(
                bool,
                "gc_off",
                "Turn off garbage collector",
            ) orelse false,
            .initial_gc = b.option(
                usize,
                "initial_gc",
                "In Kb, threshold at which the first garbage collector pass will occur",
            ) orelse if (builtin.mode == .Debug) 1 else 8,
            .next_gc_ratio = b.option(
                usize,
                "next_gc_ratio",
                "Ratio applied to get the next GC threshold",
            ) orelse 2,
            .next_full_gc_ratio = b.option(
                usize,
                "next_full_gc_ratio",
                "Ratio applied to get the next full GC threshold",
            ) orelse 4,
        },
        .jit = .{
            .debug = b.option(
                bool,
                "jit_debug",
                "Show debug information for the JIT engine",
            ) orelse false,
            .off = b.option(
                bool,
                "jit_off",
                "Turn off JIT engine",
            ) orelse false,
            .prof_threshold = b.option(
                f64,
                "jit_prof_threshold",
                "Threshold to determine if a function is hot. If the numbers of calls to it makes this percentage of all calls, it's considered hot and will be JIT compiled.",
            ) orelse 0.005,
        },
    };

    const build_mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    var exe = b.addExecutable("buzz", "src/main.zig");
    exe.setTarget(target);
    exe.setOutputDir("dist");
    exe.install();
    exe.addIncludePath("/usr/local/include");
    exe.addIncludePath("/usr/include");
    exe.linkSystemLibrary("pcre");
    if (build_options.use_mimalloc)
        exe.linkSystemLibrary("mimalloc");
    if (builtin.os.tag == .linux) {
        exe.linkLibC();
    }
    if (builtin.os.tag == .macos) {
        exe.addIncludePath("/opt/homebrew/include");
        exe.addLibraryPath("/opt/homebrew/lib");
    }

    // LLVM
    exe.addIncludePath("/Users/giann/git/incoming/llvm-project/build/include");
    exe.addLibraryPath("/Users/giann/git/incoming/llvm-project/build/lib");
    exe.linkSystemLibrary("llvm");

    exe.setBuildMode(build_mode);
    exe.setMainPkgPath(".");

    exe.addOptions("build_options", build_options.step(b));

    var lib = b.addSharedLibrary("buzz", "src/buzz_api.zig", .{ .unversioned = {} });
    lib.setOutputDir("dist/lib");
    lib.setTarget(target);
    lib.install();
    lib.addIncludePath("/usr/local/include");
    lib.addIncludePath("/usr/include");
    lib.linkSystemLibrary("pcre");
    if (build_options.use_mimalloc)
        lib.linkSystemLibrary("mimalloc");
    if (builtin.os.tag == .linux) {
        lib.linkLibC();
    }
    if (builtin.os.tag == .macos) {
        lib.addIncludePath("/opt/homebrew/include");
        lib.addLibraryPath("/opt/homebrew/lib");
    }

    // LLVM
    lib.addIncludePath("/Users/giann/git/incoming/llvm-project/build/include");
    lib.addLibraryPath("/Users/giann/git/incoming/llvm-project/build/lib");
    lib.linkSystemLibrary("llvm");

    lib.setMainPkgPath("src");
    lib.setBuildMode(build_mode);

    lib.addOptions("build_options", build_options.step(b));

    b.default_step.dependOn(&exe.step);
    b.default_step.dependOn(&lib.step);

    const lib_paths = [_][]const u8{
        "src/lib/buzz_std.zig",
        "src/lib/buzz_io.zig",
        "src/lib/buzz_gc.zig",
        "src/lib/buzz_os.zig",
        "src/lib/buzz_fs.zig",
        "src/lib/buzz_math.zig",
        "src/lib/buzz_debug.zig",
        "src/lib/buzz_buffer.zig",
    };
    // Zig only libs
    const lib_names = [_][]const u8{
        "std",
        "io",
        "gc",
        "os",
        "fs",
        "math",
        "debug",
        "buffer",
    };
    const all_lib_names = [_][]const u8{
        "std",
        "io",
        "gc",
        "os",
        "fs",
        "math",
        "debug",
        "buffer",
        "json",
        "http",
        "errors",
    };

    var libs = [_]*std.build.LibExeObjStep{undefined} ** lib_names.len;
    for (lib_paths) |lib_path, index| {
        var std_lib = b.addSharedLibrary(lib_names[index], lib_path, .{ .unversioned = {} });
        std_lib.setOutputDir("dist/lib");
        std_lib.setTarget(target);
        std_lib.install();
        std_lib.addIncludePath("/usr/local/include");
        std_lib.addIncludePath("/usr/include");
        std_lib.linkSystemLibrary("pcre");
        if (build_options.use_mimalloc)
            std_lib.linkSystemLibrary("mimalloc");
        if (builtin.os.tag == .linux) {
            std_lib.linkLibC();
        }
        if (builtin.os.tag == .macos) {
            std_lib.addIncludePath("/opt/homebrew/include");
            std_lib.addLibraryPath("/opt/homebrew/lib");
        }
        // LLVM
        std_lib.addIncludePath("/Users/giann/git/incoming/llvm-project/build/include");
        std_lib.addLibraryPath("/Users/giann/git/incoming/llvm-project/build/lib");
        std_lib.linkSystemLibrary("llvm");
        std_lib.setMainPkgPath("src");
        std_lib.setBuildMode(build_mode);
        std_lib.linkLibrary(lib);
        std_lib.addOptions("build_options", build_options.step(b));

        // Adds `$BUZZ_PATH/lib` and `/usr/local/lib/buzz` as search path for other shared lib referenced by this one (libbuzz.dylib most of the time)
        var buzz_path = std.ArrayList(u8).init(std.heap.page_allocator);
        defer buzz_path.deinit();
        buzz_path.writer().print(
            "{s}{s}lib",
            .{
                std.os.getenv("BUZZ_PATH") orelse std.fs.cwd().realpathAlloc(std.heap.page_allocator, ".") catch unreachable,
                std.fs.path.sep_str,
            },
        ) catch unreachable;
        std_lib.addRPath(buzz_path.items);
        std_lib.addRPath("/usr/local/lib/buzz");

        b.default_step.dependOn(&std_lib.step);

        libs[index] = std_lib;
    }

    // TODO: Do we need this?
    // std <- os
    libs[0].linkLibrary(libs[3]);
    // fs <- os
    libs[4].linkLibrary(libs[3]);
    // debug <- std
    libs[6].linkLibrary(libs[0]);

    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(b.getInstallStep());

    var unit_tests = b.addTest("src/main.zig");
    unit_tests.addIncludePath("/usr/local/include");
    unit_tests.addIncludePath("/usr/include");
    unit_tests.linkSystemLibrary("pcre");
    if (builtin.os.tag == .linux) {
        unit_tests.linkLibC();
    }
    if (builtin.os.tag == .macos) {
        unit_tests.addIncludePath("/opt/homebrew/include");
        unit_tests.addLibraryPath("/opt/homebrew/lib");
    }
    unit_tests.setBuildMode(.Debug);
    unit_tests.setTarget(target);
    unit_tests.addOptions("build_options", build_options.step(b));
    test_step.dependOn(&unit_tests.step);

    // Copy {lib}.buzz files to dist/lib
    for (all_lib_names) |name| {
        var lib_name = std.ArrayList(u8).init(std.heap.page_allocator);
        defer lib_name.deinit();
        lib_name.writer().print("src/lib/{s}.buzz", .{name}) catch unreachable;

        var target_lib_name = std.ArrayList(u8).init(std.heap.page_allocator);
        defer target_lib_name.deinit();
        target_lib_name.writer().print("lib/{s}.buzz", .{name}) catch unreachable;

        std.fs.cwd().copyFile(
            lib_name.items,
            std.fs.cwd().openDir("dist", .{}) catch unreachable,
            target_lib_name.items,
            .{},
        ) catch unreachable;
    }
}
