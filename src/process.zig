const std = @import("std");
const builtin = @import("builtin");

pub fn getParentPid(alloc: std.mem.Allocator, pid: std.c.pid_t) !std.c.pid_t {
    _ = alloc;
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&buf, "/proc/{d}/status", .{pid});

            const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
            defer file.close();

            var file_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            while (try file_reader.interface.takeDelimiter('\n')) |line| {
                if (std.mem.startsWith(u8, line, "PPid")) {
                    var ppid_it = std.mem.splitScalar(u8, line, ':');
                    _ = ppid_it.next(); // Skip "PPid:"
                    const ppid_str = ppid_it.next() orelse return error.PpidIsNull;
                    const ppid = try std.fmt.parseInt(
                        std.c.pid_t,
                        std.mem.trim(u8, ppid_str, " \t"),
                        10,
                    );
                    return ppid;
                }
            }

            return error.PpidIsNotSpecified;
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getProcessName(alloc: std.mem.Allocator, pid: std.c.pid_t) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&buf, "/proc/{d}/status", .{pid});

            const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
            defer file.close();

            var file_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            while (try file_reader.interface.takeDelimiter('\n')) |line| {
                if (std.mem.startsWith(u8, line, "Name")) {
                    var name_it = std.mem.splitScalar(u8, line, ':');
                    _ = name_it.next(); // Skip "Name:"
                    const process_name = std.mem.trim(
                        u8,
                        (name_it.next() orelse return error.NameIsNull),
                        " \t",
                    );
                    return try alloc.dupe(u8, process_name);
                }
            }

            return error.NameIsNotSpecified;
        },
        else => return error.UnsupportedOs,
    }
}
