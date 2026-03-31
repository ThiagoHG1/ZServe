# ZServe

Low-level networking library in Zig 0.15 focused on performance, control, and protocol-level understanding, written directly on top of `std.net` without relying on high-level stdlib abstractions. Designed to serve as the foundation for real projects — and as a portfolio of low-level network protocol implementations.

## Why from scratch?

## Why from scratch?

Zig's stdlib already provides `std.http.Client`. ZServe is built from scratch to eliminate abstraction overhead and provide full control over memory allocation, error handling, and performance at a granular level — forming the foundation for real-world systems like a fully custom Discord TUI client over raw TCP, WebSocket, and UDP protocols.

## What's implemented

### TCP Client (`core/tcp.zig`)
Bidirectional TCP connection with stream management and built-in buffered I/O.

```zig
var client = try TcpClient.connect(allocator, "example.com", 80);
defer client.close();

try client.send("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n");
const line = try client.reader.readUntil('\n');
```

### Buffered Reader (`core/http.zig`)
Ring buffer–based reader with automatic compaction and efficient stream handling.

```zig
// read until a delimiter
const line = try reader.readUntil('\n');

// read exactly N bytes
const header = try reader.readExact(4);

// fetch more data from the network
try reader.fill();
```

### Buffered Writer (`core/http.zig`)
Write buffer with explicit flush or automatic flush when full.

```zig
try writer.write("HTTP/1.1 200 OK\r\n");
try writer.write("Content-Type: text/html\r\n\r\n");
try writer.flush();
```

### TCP Server (`core/socket.zig`)
TCP server with accept loop and HTTP request parsing.

```zig
try OpenServer("0.0.0.0", 8080);
```

### Utilities (`utils/print.zig`)
Stdout print with guaranteed flush.

```zig
try print("listening on port {d}\n", .{8080});
```

## Roadmap

### Foundation (in progress)
- [X] Controlled memory allocation — clear ownership of who allocates and who frees
- [ ] Consistent error handling — custom error sets instead of `anyerror`
- [ ] Timeouts and reconnect — exponential backoff for unstable connections

### Protocols
- [ ] HTTP client — keep-alive, chunked transfer encoding
- [ ] TLS — via `std.crypto` or mbedTLS wrapper
- [ ] WebSocket — handshake and framing over HTTP
- [ ] UDP — with packet control

### Infrastructure
- [ ] Thread pool — connection handling without blocking
- [ ] DNS resolver — custom implementation without relying on the OS

### Polish
- [ ] Unit and integration tests
- [ ] HTTP/2
- [ ] API documentation

## Target project

The end goal is to use ZServe as the foundation for a Discord TUI client that runs in TTY, with support for messages, channels, guilds, and voice calls — using the Discord WebSocket Gateway and the UDP/DAVE voice protocol.

## Requirements

- Zig 0.15

## Installation

Add ZServe to your project using the Zig package manager:

\```
zig fetch --save https://github.com/ThiagoHG1/ZServe/archive/refs/heads/main.tar.gz
\```

Then in your `build.zig`, add the import:

\```zig
const zserve = b.dependency("ZServe", .{});
exe.root_module.addImport("ZServe", zserve.module("ZServe"));
\```

Then use it in your code:

\```zig
const zserve = @import("ZServe");

var client = try zserve.tcp.TcpClient.connect(allocator, "example.com", 80);
\```

## Project structure

```
src/
├── root.zig         — public library exports
├── core/
│   ├── tcp.zig      — TcpClient
│   ├── http.zig     — BufferedReader, BufferedWriter, Request
│   └── socket.zig   — OpenServer
└── utils/
    └── print.zig    — print with flush
```