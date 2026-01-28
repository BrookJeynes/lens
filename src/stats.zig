const std = @import("std");
const builtin = @import("builtin");

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

            var file_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            const dividend: usize = if (options.mb) 1000 else 1024;
            const suffix = if (options.mb) "MB" else "MiB";

            const mem_total = lbl: {
                const line = try file_reader.interface.takeDelimiter('\n') orelse return error.MemAvailableIsNotSpecified;
                var line_it = std.mem.splitScalar(u8, line, ':');
                _ = line_it.next(); // Skip "MemTotal:"
                const mem_total_with_suffix = line_it.next() orelse return error.MemTotalIsNull;
                // TODO: Is it safe to assume the suffix will only ever be "kB"?
                const mem_total_str = std.mem.trim(u8, mem_total_with_suffix, " \tkB");
                const mem_total_int = (try std.fmt.parseInt(usize, mem_total_str, 10)) / dividend;
                break :lbl mem_total_int;
            };

            _ = try file_reader.interface.takeDelimiter('\n'); // Skip "MemFree: x"

            const mem_available = lbl: {
                const line = try file_reader.interface.takeDelimiter('\n') orelse return error.MemAvailableIsNotSpecified;
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

pub fn getUptime() !struct { days: isize, minutes: isize, hours: isize } {
    switch (builtin.os.tag) {
        .linux, .openbsd => {
            var info: std.os.linux.Sysinfo = undefined;
            const result: usize = std.os.linux.sysinfo(&info);
            if (std.os.linux.E.init(result) != .SUCCESS) {
                return error.UnknownUptime;
            }
            const uptime = info.uptime;

            const uptime_days = @divTrunc(uptime, 86400);
            const uptime_hours = @divTrunc(@rem(uptime, 86400), 3600);
            const uptime_minutes = @divTrunc(@rem(uptime, 3600), 60);

            return .{
                .days = uptime_days,
                .minutes = uptime_minutes,
                .hours = uptime_hours,
            };
        },
        .macos => {
            var boot_timeval: std.posix.timeval = undefined;
            var size: usize = @sizeOf(@TypeOf(boot_timeval));
            const kern_boottime = [_]c_int{ 1, 21 }; // CTL_KERN, KERN_BOOTTIME return void on macos
            std.posix.sysctl(
                &kern_boottime,
                @ptrCast(&boot_timeval),
                &size,
                null,
                0,
            ) catch return error.SysctlFailed;

            const now = std.time.timestamp();
            const boot_time = boot_timeval.sec;
            const uptime = now - boot_time;

            const uptime_days = @divTrunc(uptime, 86400);
            const uptime_hours = @divTrunc(@rem(uptime, 86400), 3600);
            const uptime_minutes = @divTrunc(@rem(uptime, 3600), 60);

            return .{
                .days = uptime_days,
                .minutes = uptime_minutes,
                .hours = uptime_hours,
            };
        },
        else => return error.UnsupportedOs,
    }
}
