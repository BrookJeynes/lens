const std = @import("std");
const builtin = @import("builtin");

const process = @import("process.zig");

pub fn getCpu(alloc: std.mem.Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            const file = try std.fs.openFileAbsolute(
                "/proc/cpuinfo",
                .{ .mode = .read_only },
            );
            defer file.close();

            var file_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            while (try file_reader.interface.takeDelimiter('\n')) |line| {
                if (std.mem.startsWith(u8, line, "model name")) {
                    var name_it = std.mem.tokenizeScalar(u8, line, ':');
                    _ = name_it.next(); // Skip "model name :"
                    const name = name_it.next() orelse return error.ModelNameIsNull;

                    return try alloc.dupe(u8, std.mem.trim(u8, name, " \t"));
                }
            }

            return error.ModelNameIsNotSpecified;
        },
        .macos => {
            const child = try std.process.Child.run(.{
                .allocator = alloc,
                .argv = &[_][]const u8{ "sysctl", "-n", "machdep.cpu.brand_string" },
            });
            defer alloc.free(child.stderr);

            if (child.term.Exited != 0) {
                return error.FailedToReadMacCPU;
            }

            return child.stdout;
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getShell(alloc: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    if (env_map.get("SHELL")) |shell_path| {
        var shell_it = std.mem.tokenizeScalar(u8, shell_path, '/');
        var shell: []const u8 = undefined;
        // Get the last element
        while (shell_it.next()) |split| {
            shell = split;
        }

        return try alloc.dupe(u8, shell);
    }

    // If $SHELL is not set, try find the shell via pid.
    // Walk up the process tree: current -> parent -> grandparent
    const parent_info = try process.getProcessInfo(alloc, std.os.linux.getppid());
    defer alloc.free(parent_info.name);

    const grandparent_info = try process.getProcessInfo(alloc, parent_info.ppid);
    return grandparent_info.name;
}

pub fn getDesktop(alloc: std.mem.Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            var env_map = try std.process.getEnvMap(alloc);
            defer env_map.deinit();

            if (env_map.get("XDG_CURRENT_DESKTOP")) |desktop| {
                return try alloc.dupe(u8, desktop);
            }

            if (env_map.get("XDG_SESSION_DESKTOP")) |desktop| {
                return try alloc.dupe(u8, desktop);
            }

            if (env_map.get("DESKTOP_SESSION")) |desktop| {
                return try alloc.dupe(u8, desktop);
            }

            if (env_map.get("XDG_SESSION_TYPE")) |session_type| {
                if (std.mem.eql(u8, session_type, "tty")) {
                    return try alloc.dupe(u8, "Headless");
                }
            }

            return try alloc.dupe(u8, "Unknown");
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getDistro(alloc: std.mem.Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            const utsname = std.posix.uname();

            const file = try std.fs.openFileAbsolute(
                "/etc/os-release",
                .{ .mode = .read_only },
            );
            defer file.close();

            var file_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            while (try file_reader.interface.takeDelimiter('\n')) |line| {
                if (std.mem.startsWith(u8, line, "PRETTY_NAME")) {
                    var name_it = std.mem.tokenizeScalar(u8, line, '=');
                    _ = name_it.next(); // Skip "NAME="
                    const name = name_it.next() orelse return error.OsIdIsNull;

                    var name_machine_buf: [1024]u8 = undefined;
                    const name_machine = try std.fmt.bufPrint(
                        &name_machine_buf,
                        "{s} {s}",
                        .{ std.mem.trim(u8, name, "\""), std.mem.sliceTo(&utsname.machine, 0) },
                    );
                    return try alloc.dupe(u8, name_machine);
                }
            }

            return error.OsIdNotSpecified;
        },
        .macos => {
            const utsname = std.posix.uname();

            var name_machine_buf: [1024]u8 = undefined;
            const name_machine = try std.fmt.bufPrint(
                &name_machine_buf,
                "MacOS X {s}",
                .{std.mem.sliceTo(&utsname.machine, 0)},
            );
            return try alloc.dupe(u8, name_machine);
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getDistroId(alloc: std.mem.Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            const file = try std.fs.openFileAbsolute(
                "/etc/os-release",
                .{ .mode = .read_only },
            );
            defer file.close();

            var file_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            while (try file_reader.interface.takeDelimiter('\n')) |line| {
                if (std.mem.startsWith(u8, line, "ID")) {
                    var id_it = std.mem.tokenizeScalar(u8, line, '=');
                    _ = id_it.next(); // Skip "ID="
                    const id = id_it.next() orelse return error.OsIdIsNull;
                    return try alloc.dupe(u8, id);
                }
            }

            return error.OsIdNotSpecified;
        },
        .macos => {
            const utsname = std.posix.uname();
            return try alloc.dupe(u8, std.mem.sliceTo(&utsname.nodename, 0));
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getUser(alloc: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const user_env = env_map.get("USER") orelse return error.USEREnvNotSet;
    return try alloc.dupe(u8, user_env);
}

pub fn getDisk(alloc: std.mem.Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            const child = try std.process.Child.run(.{
                .allocator = alloc,
                .argv = &[_][]const u8{ "df", "-h", "--output=size,used,pcent", "/" },
            });
            defer alloc.free(child.stdout);
            defer alloc.free(child.stderr);

            if (child.term.Exited != 0) {
                return error.FailedToReadMacCPU;
            }

            var output_it = std.mem.tokenizeScalar(u8, child.stdout, '\n');
            _ = output_it.next(); // Skip headers.

            const line = std.mem.trim(
                u8,
                output_it.next() orelse return error.DiskUsageIsNull,
                " ",
            );

            var line_it = std.mem.tokenizeScalar(u8, line, ' ');

            const total = std.mem.trim(
                u8,
                line_it.next() orelse return error.DiskTotalIsNull,
                " ",
            );
            const used = std.mem.trim(
                u8,
                line_it.next() orelse return error.DiskUsedIsNull,
                " ",
            );
            const percentage = std.mem.trim(
                u8,
                line_it.next() orelse return error.DiskPercentageIsNull,
                " ",
            );

            var output_buf: [1024]u8 = undefined;
            const output = try std.fmt.bufPrint(
                &output_buf,
                "{s} / {s} ({s})",
                .{ used, total, percentage },
            );
            return try alloc.dupe(u8, output);
        },
        else => return error.UnsupportedOs,
    }
}
