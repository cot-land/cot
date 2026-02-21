# Standard Library Reference

Cot ships with 16 stdlib modules. Import them with `import "std/<module>"`.

## std/list

Dynamic array. Import: `import "std/list"`

```cot
var numbers: List(i64) = .{}
numbers.append(42)
println(numbers.get(0))    // 42
```

### List(T) Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `append` | `fn append(self, value: T) void` | Add element to end |
| `get` | `fn get(self, index: i64) T` | Get element (bounds-checked) |
| `set` | `fn set(self, index: i64, value: T) void` | Set element (bounds-checked) |
| `pop` | `fn pop(self) T` | Remove and return last element |
| `len` | `fn len(self) i64` | Element count |
| `cap` | `fn cap(self) i64` | Allocated capacity |
| `first` | `fn first(self) T` | First element |
| `last` | `fn last(self) T` | Last element |
| `isEmpty` | `fn isEmpty(self) i64` | 1 if empty |
| `insert` | `fn insert(self, index: i64, value: T) void` | Insert at index, shifting right |
| `orderedRemove` | `fn orderedRemove(self, index: i64) T` | Remove preserving order |
| `swapRemove` | `fn swapRemove(self, index: i64) T` | Remove by swapping with last |
| `indexOf` | `fn indexOf(self, value: T) i64` | First index of value, or -1 |
| `contains` | `fn contains(self, value: T) i64` | 1 if present |
| `equal` | `fn equal(self, other: List(T)) i64` | 1 if same contents |
| `reverse` | `fn reverse(self) void` | Reverse in-place |
| `clone` | `fn clone(self) List(T)` | Deep copy |
| `clear` | `fn clear(self) void` | Set count to 0, keep allocation |
| `free` | `fn free(self) void` | Deallocate memory |
| `resize` | `fn resize(self, new_len: i64) void` | Set length (grows if needed) |
| `appendNTimes` | `fn appendNTimes(self, value: T, n: i64) void` | Append same value n times |
| `appendSlice` | `fn appendSlice(self, source: i64, num: i64) void` | Append from raw pointer |
| `deleteRange` | `fn deleteRange(self, start: i64, end: i64) void` | Remove [start, end) |
| `compact` | `fn compact(self) void` | Remove consecutive duplicates |
| `sort` | `fn sort(self, cmp: fn(T, T) -> i64) void` | Sort with comparator |
| `isSorted` | `fn isSorted(self, cmp: fn(T, T) -> i64) i64` | 1 if sorted |
| `containsFunc` | `fn containsFunc(self, pred: fn(T) -> i64) i64` | 1 if any matches predicate |
| `indexOfFunc` | `fn indexOfFunc(self, pred: fn(T) -> i64) i64` | First matching index, or -1 |
| `removeIf` | `fn removeIf(self, pred: fn(T) -> i64) void` | Remove all matching elements |

---

## std/map

Hash map with linear probing. Import: `import "std/map"`

```cot
var ages: Map(i64, i64) = .{}
ages.set(1, 25)
ages.set(2, 30)
println(ages.get(1))       // 25
println(ages.has(3))       // 0
```

### Map(K, V) Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `set` | `fn set(self, key: K, value: V) void` | Insert or update |
| `get` | `fn get(self, key: K) V` | Get value (traps if missing) |
| `getOrDefault` | `fn getOrDefault(self, key: K, default: V) V` | Get or return default |
| `has` | `fn has(self, key: K) i64` | 1 if key exists |
| `delete` | `fn delete(self, key: K) void` | Remove key |
| `len` | `fn len(self) i64` | Entry count |
| `isEmpty` | `fn isEmpty(self) i64` | 1 if empty |
| `keys` | `fn keys(self) List(K)` | List of all keys |
| `values` | `fn values(self) List(V)` | List of all values |
| `clear` | `fn clear(self) void` | Remove all entries, keep allocation |
| `free` | `fn free(self) void` | Deallocate memory |

---

## std/set

Hash set (wrapper over Map). Import: `import "std/set"`

```cot
var seen: Set(i64) = .{}
seen.add(42)
println(seen.has(42))      // 1
seen.remove(42)
```

### Set(T) Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `add` | `fn add(self, value: T) void` | Add value |
| `has` | `fn has(self, value: T) i64` | 1 if present |
| `remove` | `fn remove(self, value: T) void` | Remove value |
| `len` | `fn len(self) i64` | Element count |
| `isEmpty` | `fn isEmpty(self) i64` | 1 if empty |
| `clear` | `fn clear(self) void` | Remove all, keep allocation |
| `toList` | `fn toList(self) List(T)` | Convert to List |
| `free` | `fn free(self) void` | Deallocate memory |

---

## std/string

String manipulation + StringBuilder. Import: `import "std/string"`

```cot
var s = "Hello, World!"
println(contains(s, "World"))   // true
println(toUpper(s))             // HELLO, WORLD!
println(trim("  hi  "))        // hi
```

### Free Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `charAt` | `fn charAt(s: string, index: i64) i64` | Byte at index |
| `indexOf` | `fn indexOf(s: string, needle: string) i64` | First index, or -1 |
| `lastIndexOf` | `fn lastIndexOf(s: string, needle: string) i64` | Last index, or -1 |
| `contains` | `fn contains(s: string, needle: string) bool` | True if found |
| `startsWith` | `fn startsWith(s: string, prefix: string) bool` | Prefix check |
| `endsWith` | `fn endsWith(s: string, suffix: string) bool` | Suffix check |
| `count` | `fn count(s: string, needle: string) i64` | Non-overlapping occurrences |
| `substring` | `fn substring(s: string, start: i64, end: i64) string` | Extract [start, end) |
| `trim` | `fn trim(s: string) string` | Trim whitespace both sides |
| `trimLeft` | `fn trimLeft(s: string) string` | Trim leading whitespace |
| `trimRight` | `fn trimRight(s: string) string` | Trim trailing whitespace |
| `toUpper` | `fn toUpper(s: string) string` | Uppercase (ASCII) |
| `toLower` | `fn toLower(s: string) string` | Lowercase (ASCII) |
| `replace` | `fn replace(s: string, old: string, new_s: string) string` | Replace all occurrences |
| `repeat` | `fn repeat(s: string, n: i64) string` | Repeat n times |
| `splitInto` | `fn splitInto(s: string, sep: string, result: *List(string)) void` | Split by separator |
| `parseInt` | `fn parseInt(s: string) i64` | Parse integer (0 on failure) |
| `parseIntOr` | `fn parseIntOr(s: string, default: i64) i64` | Parse with default |
| `intToString` | `fn intToString(n: i64) string` | Integer to string |
| `strEqual` | `fn strEqual(a: string, b: string) bool` | Equality check |
| `compare` | `fn compare(a: string, b: string) i64` | Lexicographic: -1, 0, 1 |
| `isDigit` | `fn isDigit(c: i64) bool` | ASCII digit? |
| `isAlpha` | `fn isAlpha(c: i64) bool` | ASCII letter? |
| `isWhitespace` | `fn isWhitespace(c: i64) bool` | Whitespace? |

### StringBuilder

```cot
var sb = StringBuilder { .buf = 0, .len = 0, .cap = 0 }
sb.append("Hello")
sb.append(", ")
sb.appendInt(42)
println(sb.toString())     // Hello, 42
sb.free()
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `append` | `fn append(self: *StringBuilder, s: string) void` | Append string |
| `appendByte` | `fn appendByte(self: *StringBuilder, b: i64) void` | Append byte |
| `appendInt` | `fn appendInt(self: *StringBuilder, n: i64) void` | Append integer as string |
| `toString` | `fn toString(self: *StringBuilder) string` | Get accumulated string |
| `length` | `fn length(self: *StringBuilder) i64` | Current length |
| `clear` | `fn clear(self: *StringBuilder) void` | Reset (keep allocation) |
| `free` | `fn free(self: *StringBuilder) void` | Free buffer |

---

## std/math

Math utilities. Import: `import "std/math"`

### Constants

`PI`, `TAU`, `E`, `LN2`, `LN10`, `MAX_I64`, `MIN_I64`

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `abs` | `fn abs(x: i64) i64` | Absolute value |
| `min` | `fn min(a: i64, b: i64) i64` | Minimum |
| `max` | `fn max(a: i64, b: i64) i64` | Maximum |
| `clamp` | `fn clamp(x: i64, lo: i64, hi: i64) i64` | Clamp to [lo, hi] |
| `fabs` | `fn fabs(x: f64) f64` | Float absolute value |
| `ceil` | `fn ceil(x: f64) f64` | Ceiling |
| `floor` | `fn floor(x: f64) f64` | Floor |
| `trunc` | `fn trunc(x: f64) f64` | Truncate toward zero |
| `round` | `fn round(x: f64) f64` | Round to nearest |
| `sqrt` | `fn sqrt(x: f64) f64` | Square root |
| `fmin` | `fn fmin(a: f64, b: f64) f64` | Float minimum |
| `fmax` | `fn fmax(a: f64, b: f64) f64` | Float maximum |
| `toInt` | `fn toInt(x: f64) i64` | Float to integer |
| `toFloat` | `fn toFloat(x: i64) f64` | Integer to float |
| `ipow` | `fn ipow(base: i64, exp: i64) i64` | Integer power |
| `fpow` | `fn fpow(base: f64, n: i64) f64` | Float power (integer exp) |

---

## std/json

JSON parser and encoder. Import: `import "std/json"`

```cot
// Parse
var root = parse("{\"name\": \"Cot\", \"version\": 3}")
println(jsonObjectGetString(root, "name"))    // Cot
println(jsonObjectGetInt(root, "version"))     // 3

// Build
var obj = jsonObject()
jsonObjectPut(obj, "hello", jsonString("world"))
jsonObjectPut(obj, "num", jsonInt(42))
println(encode(obj))    // {"hello":"world","num":42}
```

### Constructors

| Function | Signature | Description |
|----------|-----------|-------------|
| `jsonNull` | `fn jsonNull() i64` | Create null |
| `jsonBool` | `fn jsonBool(val: bool) i64` | Create boolean |
| `jsonInt` | `fn jsonInt(val: i64) i64` | Create integer |
| `jsonString` | `fn jsonString(val: string) i64` | Create string |
| `jsonArray` | `fn jsonArray() i64` | Create empty array |
| `jsonObject` | `fn jsonObject() i64` | Create empty object |

### Accessors

| Function | Signature | Description |
|----------|-----------|-------------|
| `jsonTag` | `fn jsonTag(val: i64) i64` | Type tag (0-5) |
| `jsonIsNull` | `fn jsonIsNull(val: i64) bool` | Check if null |
| `jsonGetBool` | `fn jsonGetBool(val: i64) bool` | Extract boolean |
| `jsonGetInt` | `fn jsonGetInt(val: i64) i64` | Extract integer |
| `jsonGetString` | `fn jsonGetString(val: i64) string` | Extract string |

### Array Operations

| Function | Signature | Description |
|----------|-----------|-------------|
| `jsonArrayLen` | `fn jsonArrayLen(val: i64) i64` | Array length |
| `jsonArrayGet` | `fn jsonArrayGet(val: i64, index: i64) i64` | Get element |
| `jsonArrayPush` | `fn jsonArrayPush(arr: i64, val: i64) void` | Append element |

### Object Operations

| Function | Signature | Description |
|----------|-----------|-------------|
| `jsonObjectLen` | `fn jsonObjectLen(val: i64) i64` | Key count |
| `jsonObjectPut` | `fn jsonObjectPut(obj: i64, key: string, val: i64) void` | Set key-value |
| `jsonObjectGet` | `fn jsonObjectGet(obj: i64, key: string) i64` | Get value (0 if missing) |
| `jsonObjectGetString` | `fn jsonObjectGetString(obj: i64, key: string) string` | Get string by key |
| `jsonObjectGetInt` | `fn jsonObjectGetInt(obj: i64, key: string) i64` | Get integer by key |
| `jsonObjectGetBool` | `fn jsonObjectGetBool(obj: i64, key: string) bool` | Get boolean by key |

### Parse & Encode

| Function | Signature | Description |
|----------|-----------|-------------|
| `parse` | `fn parse(input: string) i64` | Parse JSON string |
| `encode` | `fn encode(val: i64) string` | Serialize to JSON string |

---

## std/fs

File I/O. Import: `import "std/fs"`

```cot
// Read entire file
var content = readFile("config.txt")

// Write file
writeFile("output.txt", "Hello!")

// Structured file I/O
var f = openFile("data.bin", O_RDONLY)
var buf = alloc(0, 1024)
var n = try f.read(buf, 1024)
f.close()
```

### Error Type

`const FsError = error { NotFound, PermissionDenied, IoError }`

### Free Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `readFile` | `fn readFile(path: string) string` | Read entire file |
| `writeFile` | `fn writeFile(path: string, data: string) void` | Write string to file |
| `openFile` | `fn openFile(path: string, flags: i64) File` | Open with flags |
| `createFile` | `fn createFile(path: string) File` | Create/truncate for writing |
| `stdin` | `fn stdin() File` | fd 0 |
| `stdout` | `fn stdout() File` | fd 1 |
| `stderr` | `fn stderr() File` | fd 2 |

### File Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `read` | `fn read(self, buf: i64, len: i64) FsError!i64` | Read bytes |
| `write` | `fn write(self, buf: i64, len: i64) FsError!i64` | Write bytes |
| `writeAll` | `fn writeAll(self, s: string) FsError!i64` | Write string |
| `seekTo` | `fn seekTo(self, pos: i64) FsError!i64` | Seek to position |
| `seekBy` | `fn seekBy(self, delta: i64) FsError!i64` | Seek by offset |
| `getPos` | `fn getPos(self) FsError!i64` | Current position |
| `close` | `fn close(self) void` | Close file |
| `isValid` | `fn isValid(self) i64` | 1 if fd >= 0 |

### Constants

`O_RDONLY` (0), `O_WRONLY` (1), `O_RDWR` (2), `O_CREAT`, `O_TRUNC`, `O_APPEND`, `O_CREATE`, `SEEK_SET` (0), `SEEK_CUR` (1), `SEEK_END` (2)

---

## std/os

Process args and environment. Import: `import "std/os"`

```cot
// Command-line arguments
var count = argsCount()
for i in 0..count {
    println(arg(i))
}

// Exit
exit(0)
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `exit` | `fn exit(code: i64) void` | Exit process |
| `argsCount` | `fn argsCount() i64` | Number of args |
| `arg` | `fn arg(n: i64) string` | Get argument n |
| `argLen` | `fn argLen(n: i64) i64` | Length of argument n |
| `argPtr` | `fn argPtr(n: i64) i64` | Raw pointer to argument n |
| `environCount` | `fn environCount() i64` | Number of env vars |
| `environ` | `fn environ(n: i64) string` | Get env entry n |
| `environLen` | `fn environLen(n: i64) i64` | Length of env entry n |
| `environPtr` | `fn environPtr(n: i64) i64` | Raw pointer to env entry n |

---

## std/time

Timestamps and timers. Import: `import "std/time"`

```cot
var start = nanoTimestamp()
// ... work ...
var elapsed_ms = (nanoTimestamp() - start) / ns_per_ms

// Or use Timer
var t = startTimer()
// ... work ...
println(t.elapsed())    // nanoseconds
```

### Constants

`ns_per_ms` (1000000), `ns_per_s` (1000000000), `ms_per_s` (1000)

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `nanoTimestamp` | `fn nanoTimestamp() i64` | Nanoseconds since epoch |
| `milliTimestamp` | `fn milliTimestamp() i64` | Milliseconds since epoch |
| `timestamp` | `fn timestamp() i64` | Seconds since epoch |
| `startTimer` | `fn startTimer() Timer` | Create timer |

### Timer Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `elapsed` | `fn elapsed(self) i64` | Nanoseconds since start |
| `reset` | `fn reset(self) void` | Reset to now |

---

## std/random

Cryptographic random numbers. Import: `import "std/random"`

```cot
var n = randomInt()              // random i64
var dice = randomRange(6) + 1    // 1-6
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `fillBytes` | `fn fillBytes(buf: i64, len: i64) i64` | Fill buffer with random bytes |
| `randomInt` | `fn randomInt() i64` | Random 64-bit integer |
| `randomRange` | `fn randomRange(max: i64) i64` | Random in [0, max) |

---

## std/io

Buffered I/O. Import: `import "std/io"`

```cot
// Buffered reading (e.g., from stdin)
var reader = newBufferedReader(0)
var line = readLine(reader)

// Buffered writing
var writer = newBufferedWriter(1)
writeString(writer, "Hello\n")
writerFlush(writer)
```

### Reader Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `newBufferedReader` | `fn newBufferedReader(fd: i64) i64` | Create (4096 buffer) |
| `newBufferedReaderSize` | `fn newBufferedReaderSize(fd: i64, size: i64) i64` | Create (custom buffer) |
| `readByte` | `fn readByte(r: i64) i64` | Read byte, -1 for EOF |
| `readLine` | `fn readLine(r: i64) string` | Read line (no newline) |

### Writer Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `newBufferedWriter` | `fn newBufferedWriter(fd: i64) i64` | Create (4096 buffer) |
| `newBufferedWriterSize` | `fn newBufferedWriterSize(fd: i64, size: i64) i64` | Create (custom buffer) |
| `writeByte` | `fn writeByte(w: i64, b: i64) void` | Write byte |
| `writeString` | `fn writeString(w: i64, s: string) void` | Write string |
| `writerFlush` | `fn writerFlush(w: i64) void` | Flush to fd |

---

## std/encoding

Base64 and hex encoding. Import: `import "std/encoding"`

```cot
// Hex
var hex = hexEncode("Hello")     // "48656c6c6f"
var raw = hexDecode(hex)          // "Hello"

// Base64
var b64 = base64Encode("Hello")  // "SGVsbG8="
var orig = base64Decode(b64)      // "Hello"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `hexEncode` | `fn hexEncode(data: string) string` | Bytes to hex |
| `hexDecode` | `fn hexDecode(s: string) string` | Hex to bytes |
| `base64Encode` | `fn base64Encode(data: string) string` | Standard Base64 |
| `base64Decode` | `fn base64Decode(encoded: string) string` | Standard Base64 decode |
| `base64UrlEncode` | `fn base64UrlEncode(data: string) string` | URL-safe Base64 |
| `base64UrlDecode` | `fn base64UrlDecode(encoded: string) string` | URL-safe decode |

---

## std/url

URL parsing. Import: `import "std/url"`

```cot
var u = parseUrl("https://example.com:8080/path?q=1#top")
println(urlScheme(u))     // https
println(urlHost(u))       // example.com
println(urlPort(u))       // 8080
println(urlPath(u))       // /path
println(urlQuery(u))      // q=1
println(urlFragment(u))   // top
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `parseUrl` | `fn parseUrl(raw: string) i64` | Parse URL string |
| `urlToString` | `fn urlToString(url: i64) string` | Reconstruct URL |
| `urlScheme` | `fn urlScheme(url: i64) string` | Get scheme |
| `urlHost` | `fn urlHost(url: i64) string` | Get host |
| `urlPort` | `fn urlPort(url: i64) string` | Get port |
| `urlPath` | `fn urlPath(url: i64) string` | Get path |
| `urlQuery` | `fn urlQuery(url: i64) string` | Get query |
| `urlFragment` | `fn urlFragment(url: i64) string` | Get fragment |

---

## std/http

TCP sockets and HTTP. Import: `import "std/http"`

```cot
// Simple TCP server
var fd = try tcpListen(8080)
while (true) {
    var client = try acceptConnection(fd)
    var response = httpResponse(200, "Hello!")
    socketWriteString(client, response)
    socketClose(client)
}
```

### Error Type

`const NetError = error { SocketError, BindError, ListenError, ConnectError, AcceptError }`

### High-Level Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `tcpListen` | `fn tcpListen(port: i64) NetError!i64` | Create, bind, listen |
| `tcpConnect` | `fn tcpConnect(ip: i64, port: i64) NetError!i64` | Connect to server |
| `httpResponse` | `fn httpResponse(status: i64, body: string) string` | Build HTTP response |

### Socket Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `tcpSocket` | `fn tcpSocket() NetError!i64` | Create TCP socket |
| `setReuseAddr` | `fn setReuseAddr(fd: i64) void` | Set SO_REUSEADDR |
| `bindSocket` | `fn bindSocket(fd: i64, ip: i64, port: i64) NetError!i64` | Bind to address |
| `listenSocket` | `fn listenSocket(fd: i64, backlog: i64) NetError!i64` | Start listening |
| `acceptConnection` | `fn acceptConnection(fd: i64) NetError!i64` | Accept connection |
| `connectSocket` | `fn connectSocket(fd: i64, ip: i64, port: i64) NetError!i64` | Connect |
| `socketRead` | `fn socketRead(fd: i64, buf: i64, len: i64) i64` | Read from socket |
| `socketWrite` | `fn socketWrite(fd: i64, buf: i64, len: i64) i64` | Write raw bytes |
| `socketWriteString` | `fn socketWriteString(fd: i64, s: string) i64` | Write string |
| `socketClose` | `fn socketClose(fd: i64) void` | Close socket |

---

## std/sort

Sorting for List(T). Import: `import "std/sort"`

```cot
var nums: List(i64) = .{}
nums.append(3)
nums.append(1)
nums.append(2)
sort(i64)(nums)        // [1, 2, 3]
reverse(i64)(nums)     // [3, 2, 1]
```

### Functions (Generic)

| Function | Signature | Description |
|----------|-----------|-------------|
| `sort` | `fn sort(T)(list: List(T)) void` | Insertion sort (ascending) |
| `reverse` | `fn reverse(T)(list: List(T)) void` | Reverse in-place |

---

## std/async

Event loop and async I/O. Import: `import "std/async"`

```cot
var loop_fd = eventLoopCreate()
var sock = try tcpSocket()
setNonBlocking(sock)

// Async operations
var client = try await asyncAccept(loop_fd, sock)
var n = try await asyncRead(loop_fd, client, buf, 1024)
try await asyncWriteString(loop_fd, client, "OK")
```

### Error Type

`const IoError = error { ReadError, WriteError, AcceptError, ConnectError }`

### Event Loop Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `eventLoopCreate` | `fn eventLoopCreate() i64` | Create event loop (kqueue/epoll) |
| `watchRead` | `fn watchRead(loop_fd: i64, fd: i64) i64` | Watch for read events |
| `watchWrite` | `fn watchWrite(loop_fd: i64, fd: i64) i64` | Watch for write events |
| `unwatchRead` | `fn unwatchRead(loop_fd: i64, fd: i64) i64` | Stop watching reads |
| `unwatchWrite` | `fn unwatchWrite(loop_fd: i64, fd: i64) i64` | Stop watching writes |
| `eventLoopWait` | `fn eventLoopWait(loop_fd: i64, buf: i64, max: i64) i64` | Wait for events |
| `setNonBlocking` | `fn setNonBlocking(fd: i64) i64` | Set fd non-blocking |
| `eventFd` | `fn eventFd(buf: i64, index: i64) i64` | Extract fd from event |
| `isEagain` | `fn isEagain(result: i64) bool` | Check EAGAIN |

### Async I/O Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `asyncAccept` | `async fn asyncAccept(loop_fd: i64, listen_fd: i64) IoError!i64` | Accept with retry |
| `asyncRead` | `async fn asyncRead(loop_fd: i64, fd: i64, buf: i64, len: i64) IoError!i64` | Read with retry |
| `asyncWrite` | `async fn asyncWrite(loop_fd: i64, fd: i64, buf: i64, len: i64) IoError!i64` | Write with retry |
| `asyncWriteString` | `async fn asyncWriteString(loop_fd: i64, fd: i64, s: string) IoError!i64` | Write string with retry |
| `asyncConnect` | `async fn asyncConnect(loop_fd: i64, fd: i64, addr: i64, len: i64) IoError!i64` | Connect with retry |
