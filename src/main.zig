const std = @import("std");
const builtin = @import("builtin");
const stats = @import("stats.zig");
const sys_info = @import("sys_info.zig");
const environment = @import("environment.zig");
const ziggy = @import("ziggy");

const padding: u8 = 9;

const Widgets = enum {
    distro,
    uptime,
    kernel,
    desktop,
    shell,
    memory,
    battery,
    cpu,
    disk,
};

const Config = struct {
    widgets: []const Widgets,
};

const default_config = Config{
    .widgets = &[_]Widgets{
        .distro,
        .uptime,
        .kernel,
        .desktop,
        .shell,
        .memory,
        .battery,
        .cpu,
        .disk,
    },
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer _ = arena.deinit();
    var alloc = arena.allocator();

    // Read config
    const config = lbl: {
        var config_path: []u8 = undefined;
        defer alloc.free(config_path);

        var config_home: std.fs.Dir = undefined;
        defer config_home.close();

        if (try environment.get_xdg_config_home_dir()) |path| {
            config_home = path;
            config_path = try std.fs.path.join(alloc, &.{ "zysys", "config.ziggy" });
        } else {
            if (try environment.get_home_dir()) |path| {
                config_home = path;
                config_path = try std.fs.path.join(alloc, &.{ ".config", "zysys", "config.ziggy" });
            }
        }

        if (!environment.file_exists(config_home, config_path)) {
            break :lbl default_config;
        }

        const contents = config_home.readFileAlloc(alloc, config_path, 4096) catch break :lbl default_config;
        defer alloc.free(contents);
        const contentsZ = try alloc.dupeZ(u8, contents);
        defer alloc.free(contentsZ);
        break :lbl ziggy.parseLeaky(Config, alloc, contentsZ, .{}) catch default_config;
    };

    // Print header
    const user_env = try sys_info.getUser(alloc);
    defer alloc.free(user_env);
    const distro_id = try sys_info.getDistroId(alloc);
    defer alloc.free(distro_id);

    var header_buf: [1024]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "{s}@{s}\n", .{ user_env, distro_id });

    try stdout.writeAll(header);
    try stdout.print("{s[str]:-<[count]}\n", .{ .str = "-", .count = header.len + 1 });

    // Print widgets
    for (config.widgets) |widget| {
        switch (widget) {
            .distro => {
                const distro = sys_info.getDistro(alloc) catch continue;
                defer alloc.free(distro);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "distro", .stat = distro, .padding = padding },
                );
            },
            .uptime => {
                const uptime = stats.getUptime() catch continue;

                try stdout.print(
                    "{s[header]: <[padding]}{[days]}d {[hours]}h {[minutes]}m\n",
                    .{
                        .header = "uptime",
                        .days = uptime.days,
                        .hours = uptime.hours,
                        .minutes = uptime.minutes,
                        .padding = padding,
                    },
                );
            },
            .kernel => {
                const utsname = std.posix.uname();
                const release = std.mem.sliceTo(&utsname.release, 0);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "kernel", .stat = release, .padding = padding },
                );
            },
            .desktop => {
                const desktop = sys_info.getDesktop(alloc) catch continue;
                defer alloc.free(desktop);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "desktop", .stat = desktop, .padding = padding },
                );
            },
            .shell => {
                const shell = sys_info.getShell(alloc) catch continue;
                defer alloc.free(shell);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "shell", .stat = shell, .padding = padding },
                );
            },
            .memory => {
                const mem = stats.getMemory(alloc, .{ .mb = true }) catch continue;
                defer alloc.free(mem);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "memory", .stat = mem, .padding = padding },
                );
            },
            .battery => {
                const battery = stats.getBattery(alloc) catch continue;
                defer alloc.free(battery);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "battery", .stat = battery, .padding = padding },
                );
            },
            .cpu => {
                const cpu = sys_info.getCpu(alloc) catch continue;
                defer alloc.free(cpu);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "cpu", .stat = cpu, .padding = padding },
                );
            },
            .disk => {
                const disk = sys_info.getDisk(alloc) catch continue;
                defer alloc.free(disk);

                try stdout.print(
                    "{s[header]: <[padding]}{s[stat]}\n",
                    .{ .header = "disk", .stat = disk, .padding = padding },
                );
            },
        }
    }
}
