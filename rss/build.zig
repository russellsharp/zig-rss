const std = @import("std");
const module = @import("std").Build.Module;
const Step = std.Build.Step;

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("root", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "rss",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "rss" is the name you will use in your source code to
                // import this module (e.g. `@import("rss")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "rss", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    // const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const test_runner = std.Build.Step.Compile.TestRunner{
        .path = b.path("src/testrunner/zrunner/zrunner.zig"),
        .mode = .simple,
    };

    exe_tests.test_runner = test_runner;
    mod_tests.test_runner = test_runner;

    const a = b.allocator;

    const options = b.addOptions();
    options.addOption(bool, "enable_logging", true);

    mod.addOptions("options", options);
    exe.root_module.addOptions("options", options);
    exe_tests.root_module.addOptions("options", options);

    var modules_custom: std.StringHashMap(*module) = .init(a);
    _ = &modules_custom;

    var module_collection = std.ArrayList(moduleDetails).empty;
    _ = &module_collection;
    _ = module_collection.append(a, .{ .name = "xml", .path = "src/xml/src/xml.zig", .testStepName = "testXml", .testStepDescription = "Tests for xml module." }) catch unreachable;
    _ = module_collection.append(a, .{ .name = "utilities", .path = "src/utilities/utilities.zig", .options = options, .testStepName = "testUtilities", .testStepDescription = "Tests for utilities module." }) catch unreachable;
    _ = module_collection.append(a, .{ .name = "rss", .path = "src/rss/rss.zig", .dependencies = &.{ "utilities", "xml", "options" }, .options = options, .testStepName = "testRss", .testStepDescription = "Tests for rss module." }) catch unreachable;
    _ = module_collection.append(a, .{ .name = "host", .path = "src/host/host.zig", .dependencies = &.{ "utilities", "rss", "options" }, .options = options, .testStepName = "testHost", .testStepDescription = "Tests for host module." }) catch unreachable;

    var roots = std.ArrayList(*Step.Compile).empty;
    roots.appendSlice(a, &.{ exe, mod_tests, exe_tests }) catch unreachable;

    buildDependencies(b, &module_collection, &modules_custom, roots.toOwnedSlice(a) catch unreachable, target, optimize);

    buildTestSteps(b, &module_collection, &modules_custom, test_runner);

    // A run step that will run the second test executable.
    // const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    // const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}

const moduleDetails = struct {
    name: []const u8,
    path: []const u8,
    dependencies: ?[]const []const u8 = null,
    options: ?*std.Build.Step.Options = null,
    testStepName: ?[]const u8 = null,
    testStepDescription: ?[]const u8 = null,
};

fn buildDependencies(b: *std.Build, module_collection: *std.ArrayList(moduleDetails), modules_custom: *std.StringHashMap(*module), roots: []*Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    for (module_collection.items) |m| {
        var new_module = b.addModule(m.name, .{ .root_source_file = b.path(m.path), .target = target, .optimize = optimize });
        modules_custom.put(m.name, new_module) catch unreachable;
        if (m.dependencies != null) {
            for (m.dependencies.?) |d| {
                if (modules_custom.contains(d))
                    new_module.addImport(d, modules_custom.get(d).?);
            }
        }

        if (m.options) |option| {
            new_module.addOptions("options", option);
        }

        for (roots) |root| {
            root.root_module.addImport(m.name, new_module);
        }
    }
}

fn buildTestSteps(b: *std.Build, details: *std.ArrayList(moduleDetails), modules_custom: *std.StringHashMap(*module), runner: Step.Compile.TestRunner) void {
    for (details.items) |detail| {
        if (detail.testStepName == null) continue;

        const mod = modules_custom.get(detail.name);

        if (mod) |a_module| {
            const mod_tests = b.addTest(.{
                .root_module = a_module,
                .test_runner = runner,
            });

            // create and add a test command for testing utilities
            var run_tests = b.addRunArtifact(mod_tests);
            _ = &run_tests;
            const test_step = b.step(detail.testStepName.?, detail.testStepDescription orelse "");
            test_step.dependOn(&run_tests.step);
        }
    }
}
