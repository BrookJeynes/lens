const std = @import("std");

const BufferedFileIterator = @This();

alloc: std.mem.Allocator,
buf_reader: std.io.BufferedReader(4096, std.io.AnyReader),
line: std.ArrayList(u8),

pub fn init(alloc: std.mem.Allocator, reader: std.io.AnyReader) BufferedFileIterator {
    return BufferedFileIterator{
        .alloc = alloc,
        .buf_reader = std.io.bufferedReader(reader),
        .line = std.ArrayList(u8).init(alloc),
    };
}

pub fn deinit(self: BufferedFileIterator) void {
    self.line.deinit();
}

pub fn next(self: *BufferedFileIterator) !?[]const u8 {
    self.line.clearRetainingCapacity();
    const writer = self.line.writer();
    self.buf_reader.reader().streamUntilDelimiter(writer, '\n', null) catch |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };
    return self.line.items;
}
