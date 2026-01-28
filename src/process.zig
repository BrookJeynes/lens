const std = @import("std");
const builtin = @import("builtin");

pub const ProcessInfo = struct {
    name: []const u8,
    ppid: std.c.pid_t,
};

pub fn getProcessInfo(alloc: std.mem.Allocator, pid: std.c.pid_t) !ProcessInfo {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid});

            const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
            defer file.close();

            var file_buffer: [4096]u8 = undefined;
            const bytes_read = try file.readAll(&file_buffer);
            const content = file_buffer[0..bytes_read];

            const name_start = std.mem.indexOf(u8, content, "(") orelse return error.InvalidStatFormat;
            const name_end = std.mem.lastIndexOf(u8, content, ")") orelse return error.InvalidStatFormat;

            if (name_end <= name_start + 1) return error.InvalidStatFormat;

            const name = try alloc.dupe(u8, content[name_start + 1 .. name_end]);

            const after_name = content[name_end + 1 ..];
            var field_it = std.mem.tokenizeAny(u8, after_name, " \t\n");

            // Skip state field
            _ = field_it.next() orelse return error.InvalidStatFormat;

            const ppid_str = field_it.next() orelse return error.InvalidStatFormat;
            const ppid = try std.fmt.parseInt(std.c.pid_t, ppid_str, 10);

            return ProcessInfo{
                .name = name,
                .ppid = ppid,
            };
        },
        else => return error.UnsupportedOs,
    }
}
