const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "zc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.link_libc = true;
    lib.root_module.stack_check = false;
    linkMlir(lib.root_module);
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.link_libc = true;
    linkMlir(tests.root_module);
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run libzc tests").dependOn(&run_tests.step);
}

fn linkMlir(module: *std.Build.Module) void {
    // libcir (CIR dialect + C API)
    module.addObjectFile(.{ .cwd_relative = "../libcir/build/libCIR.a" });

    // MLIR libraries
    const p = "/opt/homebrew/Cellar/llvm@20/20.1.8/lib/";
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRCAPIIR.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRIR.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRSupport.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRDialect.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRBytecodeWriter.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRBytecodeReader.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRBytecodeOpInterface.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRPass.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRAsmParser.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRParser.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libMLIRFuncDialect.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libLLVMSupport.a" });
    module.addObjectFile(.{ .cwd_relative = p ++ "libLLVMDemangle.a" });

    module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/Cellar/llvm@20/20.1.8/include" });
    module.addIncludePath(.{ .cwd_relative = "../libcir/include" });
    module.addIncludePath(.{ .cwd_relative = "../libcir/c-api" });

    const sdk_path = "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/lib";
    module.addObjectFile(.{ .cwd_relative = sdk_path ++ "/libc++.tbd" });
}
