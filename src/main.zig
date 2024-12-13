//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;
const testing = std.testing;

const CommandTupleList = std.ArrayList(CommandTuple);

const Address = union(enum) {
    line: u64,
    context: []u8,
    last: void,
};

const Addresses = union(enum){
    none: void,
    one: Address,
    two: struct {
        start: Address,
        stop: Address,
        active: bool = false,
    },
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

var PatternSpace = [8192]u8{};
var HoldSpace = [8192]u8{};

pub fn main() !void {
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

// pub fn parseCommands(allocator: mem.Allocator, input: *io.StreamSource) ![]CommandTuple {
//     var command_tuple = CommandTupleList.init(allocator);
//     errdefer command_tuple.deinit();

//     // parseAddress
//     // parseCommand

//     return try command_tuple.toOwnedSlice();
// }

// pub fn parseCommand(input: *io.StreamSource) !?CommandTuple {

// }

fn parseAddresses(input: *io.StreamSource) !Addresses {
    const addr1 = try parseAddress(input) orelse return .none;
    try gobbleSpace(input);
    if (try input.reader().readByte() != ',') {
        try input.seekBy(-1);
        return .{ .one = addr1 };
    }
    const addr2 = try parseAddress(input) orelse return error.ExpectedAddress;
    return .{ .two = .{ .start = addr1, .stop = addr2 }};
}

fn parseAddress(input: *io.StreamSource) !?Address {
    const byte = try input.reader().readByte();
    if (std.ascii.isDigit(byte)) {
        try input.seekBy(-1);
        return Address{ .line = try parseLineNumber(input) };
    } else if (byte == '$') {
        return Address.last;
    } else if (byte == '/') {
        // TODO regex
        return error.RegexUnsupported;
    } else if (byte == '\\') {
        // TODO regex
        return error.RegexUnsupported;
    } else {
        return null;
    }
}

fn gobbleSpace(input: *io.StreamSource) !void {
    const reader = input.reader();
    var byte = try reader.readByte();
    while (byte == ' ' or byte == '\t') {
        byte = reader.readByte() catch |err| {
            if (err == error.EndOfStream)
                break;
            return err;
        };
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

test parseAddresses {
    var source1 = testSource("123p");
    const addr1 = try parseAddresses(&source1);
    try testing.expectEqual(Addresses{ .one = .{ .line = 123 }}, addr1);

    var source2 = testSource("123,456");
    const addr2 = try parseAddresses(&source2);
    try testing.expectEqual(Addresses{ .two = .{ .start = .{ .line = 123 }, .stop = .{ .line = 456}}}, addr2);

    var source3 = testSource("p");
    const addr3 = try parseAddresses(&source3);
    try testing.expectEqual(Addresses.none, addr3);

    var source4 = testSource("123,d");
    try testing.expectError(error.ExpectedAddress, parseAddresses(&source4));

    var source5 = testSource("123,$");
    const addr5 = try parseAddresses(&source5);
    try testing.expectEqual(Addresses{ .two = .{ .start = .{ .line = 123 }, .stop = .last }}, addr5);

}

test parseAddress {
    var source1 = testSource("123");
    const addr1 = try parseAddress(&source1);
    try testing.expectEqual(Address{ .line = 123 }, addr1);

    var source2 = testSource("$");
    const addr2 = try parseAddress(&source2);
    try testing.expectEqual(Address.last, addr2);

    var source3 = testSource("-13");
    const addr3 = try parseAddress(&source3);
    try testing.expectEqual(null, addr3);

    var source4 = testSource("d");
    const addr4 = try parseAddress(&source4);
    try testing.expectEqual(null, addr4);

    var source5 = testSource("");
    try testing.expectError(error.EndOfStream, parseAddress(&source5));

    var source6 = testSource("/dog/");
    try testing.expectError(error.RegexUnsupported, parseAddress(&source6));

    var source7 = testSource("\\gcatg");
    try testing.expectError(error.RegexUnsupported, parseAddress(&source7));
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
