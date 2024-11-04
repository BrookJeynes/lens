const std = @import("std");
const builtin = @import("builtin");
const BufferedFileIterator = @import("buffered_file_iter.zig");

pub fn getBattery(alloc: std.mem.Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            var dir = try std.fs.openDirAbsolute("/sys/class/power_supply/", .{ .iterate = true });
            defer dir.close();

            var smallest_battery: ?usize = null;

            // Walk dir and find the smallest battery.
            var it = dir.iterate();
            while (try it.next()) |entry| {
                if (std.mem.startsWith(u8, entry.name, "BAT")) {
                    const battery_no = try std.fmt.parseInt(usize, std.mem.trimLeft(u8, entry.name, "BAT"), 10);
                    if (smallest_battery) |smallest| {
                        if (battery_no < smallest) smallest_battery = battery_no;
                    } else {
                        smallest_battery = battery_no;
                    }
                }
            }

            if (smallest_battery == null) return error.NoBatteryDetected;

            // Read battery capacity.
            var battery_capacity_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const battery_capacity_path = try std.fmt.bufPrint(
                &battery_capacity_path_buf,
                "/sys/class/power_supply/BAT{d}/capacity",
                .{smallest_battery.?},
            );
            const battery_capacity_file = try std.fs.openFileAbsolute(
                battery_capacity_path,
                .{ .mode = .read_only },
            );
            defer battery_capacity_file.close();

            var battery_capacity_buf: [1024]u8 = undefined;
            const battery_capacity_bytes = try battery_capacity_file.readAll(&battery_capacity_buf);
            const battery_capacity = try std.fmt.parseInt(
                usize,
                std.mem.trim(u8, battery_capacity_buf[0..battery_capacity_bytes], "\n"),
                10,
            );

            // Read battery status.
            var battery_status_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const battery_status_path = try std.fmt.bufPrint(
                &battery_status_path_buf,
                "/sys/class/power_supply/BAT{d}/status",
                .{smallest_battery.?},
            );
            const battery_status_file = try std.fs.openFileAbsolute(
                battery_status_path,
                .{ .mode = .read_only },
            );
            defer battery_status_file.close();

            var battery_status_buf: [1024]u8 = undefined;
            const battery_status_bytes = try battery_status_file.readAll(&battery_status_buf);
            const battery_status = std.mem.trim(
                u8,
                battery_status_buf[0..battery_status_bytes],
                "\n",
            );

            var output_buf: [1024]u8 = undefined;
            const output = try std.fmt.bufPrint(
                &output_buf,
                "{d}% ({s})",
                .{ battery_capacity, battery_status },
            );
            return try alloc.dupe(u8, output);
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getMemory(alloc: std.mem.Allocator, options: struct { mb: bool }) ![]const u8 {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            const file = try std.fs.openFileAbsolute("/proc/meminfo", .{ .mode = .read_only });
            defer file.close();

            var file_it = BufferedFileIterator.init(alloc, file.reader().any());
            defer file_it.deinit();

            const dividend: usize = if (options.mb) 1000 else 1024;
            const suffix = if (options.mb) "MB" else "MiB";

            const mem_total = lbl: {
                const line = try file_it.next() orelse return error.MemTotalIsNotSpecified;
                var line_it = std.mem.splitScalar(u8, line, ':');
                _ = line_it.next(); // Skip "MemTotal:"
                const mem_total_with_suffix = line_it.next() orelse return error.MemTotalIsNull;
                // TODO: Is it safe to assume the suffix will only ever be "kB"?
                const mem_total_str = std.mem.trim(u8, mem_total_with_suffix, " \tkB");
                const mem_total_int = (try std.fmt.parseInt(usize, mem_total_str, 10)) / dividend;
                break :lbl mem_total_int;
            };

            _ = try file_it.next(); // Skip "MemFree: x"

            const mem_available = lbl: {
                const line = try file_it.next() orelse return error.MemAvailableIsNotSpecified;
                var line_it = std.mem.splitScalar(u8, line, ':');
                _ = line_it.next(); // Skip "MemAvailable:"
                const mem_available_with_suffix = line_it.next() orelse return error.MemAvailableIsNull;
                // TODO: Is it safe to assume it'll only ever be "kB"?
                const mem_available_str = std.mem.trim(u8, mem_available_with_suffix, " \tkB");
                const mem_available_int = (try std.fmt.parseInt(usize, mem_available_str, 10)) / dividend;
                break :lbl mem_available_int;
            };

            const mem_used = mem_total - mem_available;
            const mem_percentage: usize = @intFromFloat(
                (@as(f32, @floatFromInt(mem_used)) / @as(f32, @floatFromInt(mem_total))) * 100,
            );

            var buf: [1024]u8 = undefined;
            const mem_str = try std.fmt.bufPrint(&buf, "{d} / {d} {s} ({d}%)", .{
                mem_used,
                mem_total,
                suffix,
                mem_percentage,
            });
            return try alloc.dupe(u8, mem_str);
        },
        else => return error.UnsupportedOs,
    }
}

pub fn getUptime() !struct { days: usize, minutes: usize, hours: usize } {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            const file = try std.fs.openFileAbsolute(
                "/proc/uptime",
                .{ .mode = .read_only },
            );
            defer file.close();

            var uptime_buf: [1024]u8 = undefined;
            const bytes = try file.readAll(&uptime_buf);
            const uptime_str = uptime_buf[0..bytes];

            var uptime_it = std.mem.splitScalar(u8, uptime_str, ' ');
            const uptime: usize = @intFromFloat(
                try std.fmt.parseFloat(
                    f32,
                    uptime_it.next() orelse return error.UptimeIsNull,
                ),
            );

            const uptime_days = uptime / 86400;
            const uptime_hours = (uptime % 86400) / 3600;
            const uptime_minutes = (uptime % 3600) / 60;

            return .{
                .days = uptime_days,
                .minutes = uptime_minutes,
                .hours = uptime_hours,
            };
        },
        else => return error.UnsupportedOs,
    }
}
