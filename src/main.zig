//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;
const testing = std.testing;
const log = std.log;

const CommandTupleList = std.ArrayList(CommandTuple);

const Address = union(enum) {
    line: u64,
    context: []const u8,
    last: void,

    pub fn deinit(self: Address, allocator: mem.Allocator) void {
        switch (self) {
            .context => |context| allocator.free(context),
            else => {}
        }
    }
};

const TwoAddress = struct {
    start: Address,
    stop: Address,
    active: bool = false,
};

const Addresses = union(enum){
    none: void,
    one: Address,
    two: TwoAddress,

    pub fn deinit(self: Addresses, allocator: mem.Allocator) void {
        switch (self) {
            .one => |addr| addr.deinit(allocator),
            .two => |addrs| {
                addrs.start.deinit(allocator);
                addrs.stop.deinit(allocator);
            },
            else => {}
        }
    }
};

const Command = union(enum) {
    // Sub-expression
    open_brace: void,
    close_brace: void,
    // Write text to standard output before reading the next line of input.
    a: []u8,
    // Branch to label, or end of script if empty.
    b: Label,
    // Delete pattern space. With a 0 or 1 address or at the end of a
    // 2-address range, place text on the output and start the next
    // cycle.
    c: []u8,
    // Delete the pattern space and start the next cycle.
    d: void,
    // If the pattern space contains no <newline>, delete the pattern
    // space and start a normal new cycle as if the d command was
    // issued. Otherwise, delete the initial segment of the pattern
    // space through the first <newline>, and start the next cycle
    // with the resultant pattern space and without reading any new
    // input.
    d_upper: void,
    // Replace the contents of the pattern space with the hold space.
    g: void,
    // Append to the pattern space a <newline> followed by the contents of the hold space.
    g_upper: void,
    // Replace the contents of the hold space with the pattern space.
    h: void,
    // Append a newline and the contents of the pattern space to the
    // hold space.
    h_upper: void,
    // Write text to standard output.
    i: []u8,
    // Write the pattern space to standard output, with all escape
    // sequences written with backslashes and other non-printable
    // characters written in octal. Long lines are folded with a
    // backslash and a newline, and newlines are marked with a $.
    l: void,
    // Write the pattern space to standard output if it has not been
    // surpressed, and replace the pattern space with the next line of
    // input. If the next line is not available, branch to the end of
    // the script and quit.
    n: void,
    // Append a newline and the next line of input to the pattern
    // space. Note that the current line number changes. If there is
    // no new line available. If no new line of input is available,
    // branch to the end of the script and quit.
    n_upper: void,
    // Write the pattern space to stadnard output.
    p: void,
    // Write the pattern space, up to the first newline, to standard output.
    p_upper: void,
    // Branch to the end of the script and quit.
    q: void,
    // Copy the contents of file to standard output. If no file, treat
    // it as empty.
    r: File,
    // TODO, big
    s: SubArgs,
    // Test and jump to label. If any substitutions have been made,
    // jump to label, or end of file if no label is specified.
    t: Label,
    // Append pattern space to file.
    w: File,
    // Exchange the contents of the pattern and hold space.
    x: void,
    // Replace the occurance of characters from the original string 1
    // with the corresponding character form string 2.
    y: struct {
        original: []u8,
        replacement: []u8,
    },
    // Create label. Does not do anything.
    label: Label,
    // Write the current line number to standard output.
    equal: void,
    // Does nothing.
    empty: void,
    // Does nothing and ignores everything until the end of the line.
    hash: void,
};

const SubArgs = struct {
    match: u8,
    replacemet: u8,
    flags: struct {
        occurance: u32,
        global: bool,
        print: bool,
        write_file: File,
    }
};

const File = struct {
    name: []u8,
    handle: std.fs.File,
};

const Label = []u8;

const CommandTuple = struct {
    addresses: Addresses,
    invert_match: bool,
    command: Command,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    if (std.os.argv.len < 2) {
        return error.NotEnoughArguments;
    }

    const comm: []const u8 = std.mem.span(std.os.argv[1]);
    const stream = io.fixedBufferStream(comm);
    var input = io.StreamSource{.const_buffer = stream};
    const commands = try parseCommands(allocator, &input);

    for (commands) |command| {
        std.log.debug("addr: {any}, inverted: {any}, command: {any}", .{ command.addresses, command.invert_match, command.command });
    }

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // Don't forget to flush!


    // parseCommands
    // open files
    // read line
    // if end of stream, activate $ matches with last pattern space
    // execute commands
    // print line if not suppressed
    // pre-next-line-commands (append, etc.)
    // back to read line
}


const State = struct {
    patternSpace: [8192]u8,
    holdSpace: [8192]u8,
    line: u64,
    commandTuples: []CommandTuple,
};

pub fn parseCommands(allocator: mem.Allocator, input: *io.StreamSource) ![]CommandTuple {
    var command_tuples = CommandTupleList.init(allocator);
    errdefer command_tuples.deinit();

    log.debug("parsecommand pos: {d}", .{ try input.getPos() });

    cmd_loop: while (true) {
        gobbleSpace(input) catch |err| switch(err) {
            error.EndOfStream => break :cmd_loop,
            else => return err
        };

        log.debug("after gobble: {d}", .{ try input.getPos() });

        const byte = try input.reader().readByte();
        if (byte == ';' or byte == '\n')
            continue
        else {
            log.debug("parseCommands byte put back: {c}", .{ byte });
            try input.seekBy(-1);
        }

        const command_tuple = try parseCommandTuple(allocator, input);
        if (command_tuple) |exists|
            try command_tuples.append(exists)
        else
            break;
    }

    return try command_tuples.toOwnedSlice();
}

pub fn parseCommandTuple(allocator: mem.Allocator, input: *io.StreamSource) !?CommandTuple {
    // if (try input.getPos() == try input.getEndPos()) {
    //     return null;
    // }
    log.debug("in parseCommandTuple", .{});
    const addrs = try parseAddresses(allocator, input);
    try gobbleSpace(input);
    var inverted = false;
    const byte = try input.reader().readByte();
    if (byte == '!') {
        inverted = true;
    } else {
        try input.seekBy(-1);
    }
    try gobbleSpace(input);
    const command = try parseCommand(allocator, input);

    return CommandTuple{ .addresses = addrs, .command = command, .invert_match = inverted };
}

fn parseCommand(allocator: mem.Allocator, input: *io.StreamSource) !Command {
    _ = allocator;
    const reader = input.reader();

    const char = try reader.readByte();
    const command = switch (char) {
        '{' => Command.open_brace,
        '}' => Command.close_brace,
        'a' => error.CommandNotImplemented,
        'b' => error.CommandNotImplemented,
        'c' => error.CommandNotImplemented,
        'd' => Command.d,
        'D' => Command.d_upper,
        'g' => Command.g,
        'G' => Command.g_upper,
        'h' => Command.h,
        'H' => Command.h_upper,
        'i' => error.CommandNotImplemented,
        'l' => Command.l,
        'n' => Command.n,
        'N' => Command.n_upper,
        'p' => Command.p,
        'P' => Command.p_upper,
        'q' => Command.q,
        'r' => error.CommandNotImplemented,
        's' => error.CommandNotImplemented,
        't' => error.CommandNotImplemented,
        'w' => error.CommandNotImplemented,
        'x' => Command.x,
        'y' => error.CommandNotImplemented,
        ':' => error.CommandNotImplemented,
        '=' => Command{ .equal = {} },
        '#' => error.CommandNotImplemented,
        else => error.UnsupportedCommand,
    };

    gobbleSpace(input) catch |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    };

    return command;
}

fn parseAddresses(allocator: mem.Allocator, input: *io.StreamSource) !Addresses {
    const addr1 = try parseAddress(allocator, input) orelse return .none;
    try gobbleSpace(input);
    if (try input.reader().readByte() != ',') {
        try input.seekBy(-1);
        return .{ .one = addr1 };
    }
    const addr2 = try parseAddress(allocator, input) orelse return error.ExpectedAddress;
    return .{ .two = .{ .start = addr1, .stop = addr2 }};
}

fn parseAddress(allocator: mem.Allocator, input: *io.StreamSource) !?Address {
    const byte = try input.reader().readByte();
    if (std.ascii.isDigit(byte)) {
        try input.seekBy(-1);
        return Address{ .line = try parseLineNumber(input) };
    } else if (byte == '$') {
        return Address.last;
    } else if (byte == '/') {
        return Address{ .context = try parseContext(allocator, input, false) };
    } else if (byte == '\\') {
        return Address{ .context = try parseContext(allocator, input, true) };
    } else {
        return null;
    }
}

fn gobbleSpace(input: *io.StreamSource) !void {
    const reader = input.reader();
    var byte: u8 = ' ';
    while (byte == ' ' or byte == '\t') {
        byte = try reader.readByte();
    }
    try input.seekBy(-1);
}

fn parseLineNumber(input: *io.StreamSource) !u64 {
    var backing_buf: [1024]u8 = undefined;
    var buffer = std.io.fixedBufferStream(&backing_buf);
    var end_of_stream = false;
    const writer = buffer.writer();

    var byte = try input.reader().readByte();
        while (ascii.isDigit(byte)) {
        try writer.writeByte(byte);
        byte = input.reader().readByte() catch |err| {
            if (err == error.EndOfStream) {
                end_of_stream = true;
                break;
            }
            return err;
        };
    }

    if (!end_of_stream)
        try input.seekBy(-1);

    return try fmt.parseInt(u64, buffer.getWritten(), 0);
}

fn parseContext(allocator: mem.Allocator, input: *io.StreamSource, special: bool) ![]const u8 {
    const reader = input.reader();
    const final = blk: {
        if (!special)
            break :blk '/';
        break :blk try reader.readByte();
    };
    var escaped = false;
    var address = std.ArrayList(u8).init(allocator);
    errdefer address.deinit();

    while (true) {
        const char = try reader.readByte();
        if (escaped) {
            switch (char) {
                'n' => try address.append('\n'),
                else => try address.append(char),
            }
            escaped = false;
        } else if (char == final) {
            return try address.toOwnedSlice();
        } else if (char == '\\') {
            escaped = true;
        } else {
            try address.append(char);
        }
    }
}

test parseAddresses {
    const allocator = testing.allocator;

    var source1 = testSource("123p");
    const addr1 = try parseAddresses(allocator, &source1);
    try testing.expectEqual(Addresses{ .one = .{ .line = 123 }}, addr1);

    var source2 = testSource("123,456");
    const addr2 = try parseAddresses(allocator, &source2);
    try testing.expectEqual(Addresses{ .two = .{ .start = .{ .line = 123 }, .stop = .{ .line = 456}}}, addr2);

    var source3 = testSource("p");
    const addr3 = try parseAddresses(allocator, &source3);
    try testing.expectEqual(Addresses.none, addr3);

    var source4 = testSource("123,d");
    try testing.expectError(error.ExpectedAddress, parseAddresses(allocator, &source4));

    var source5 = testSource("123,$");
    const addr5 = try parseAddresses(allocator, &source5);
    try testing.expectEqual(Addresses{ .two = .{ .start = .{ .line = 123 }, .stop = .last }}, addr5);

}

test parseAddress {
    const allocator = testing.allocator;

    var source1 = testSource("123");
    const addr1 = try parseAddress(allocator, &source1);
    try testing.expectEqual(Address{ .line = 123 }, addr1);

    var source2 = testSource("$");
    const addr2 = try parseAddress(allocator, &source2);
    try testing.expectEqual(Address.last, addr2);

    var source3 = testSource("-13");
    const addr3 = try parseAddress(allocator, &source3);
    try testing.expectEqual(null, addr3);

    var source4 = testSource("d");
    const addr4 = try parseAddress(allocator, &source4);
    try testing.expectEqual(null, addr4);

    var source5 = testSource("");
    try testing.expectError(error.EndOfStream, parseAddress(allocator, &source5));

    var source6 = testSource("/dog\\//");
    const addr6 = try parseAddress(allocator, &source6);
    defer addr6.?.deinit(allocator);
    try testing.expectEqualDeep(Address{ .context = "dog/" }, addr6);

    var source7 = testSource("\\c\\cat\\nc");
    const addr7 = try parseAddress(allocator, &source7);
    defer addr7.?.deinit(allocator);
    try testing.expectEqualDeep(Address{ .context = "cat\n" }, addr7);
}

test parseLineNumber {
    var source1 = testSource("123");
    const line1 = try parseLineNumber(&source1);
    try testing.expectEqual(123, line1);

    var source2 = testSource("1");
    const line2 = try parseLineNumber(&source2);
    try testing.expectEqual(1, line2);

    var source3 = testSource("10d");
    const line3 = try parseLineNumber(&source3);
    try testing.expectEqual(10, line3);
}

test parseContext {
    const allocator = testing.allocator;

    var source = testSource("123/");
    var line = try parseContext(allocator, &source, false);
    try testing.expectEqualSlices(u8, "123", line);
    allocator.free(line);

    source = testSource("c123c");
    line = try parseContext(allocator, &source, true);
    try testing.expectEqualSlices(u8, "123", line);
    allocator.free(line);
}

fn testSource(input: []const u8) io.StreamSource {
    const stream = io.fixedBufferStream(input);
    return io.StreamSource{ .const_buffer = stream };
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }

// test "fuzz example" {
//     // Try passing `--fuzz` to `zig build` and see if it manages to fail this test case!
//     const input_bytes = std.testing.fuzzInput(.{});
//     try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input_bytes));
// }
