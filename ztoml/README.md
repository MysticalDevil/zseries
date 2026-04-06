# ztoml

A TOML parsing library for Zig 0.16+ with DOM-style API.

## Features

- Parse TOML source into a DOM tree (Value type)
- Serialize Value back to TOML string
- Support for basic TOML types: strings, integers, floats, booleans, arrays, tables
- Dotted keys and nested tables
- Array of tables (`[[table]]` syntax)
- Inline tables

## Usage

```zig
const std = @import("std");
const ztoml = @import("ztoml");

const source =
    \\[server]
    \\host = "localhost"
    \\port = 8080
    \\
    \\[database]
    \\name = "mydb"
    \\connections = 10
;

var value = try ztoml.parseString(allocator, source);
defer value.deinit(allocator);

// Access values
const host = value.get("server").?.get("host").?.getString();
const port = value.get("server").?.get("port").?.getInteger();
```

## API

### Parsing

- `parseString(allocator, source)` - Parse TOML string into Value
- `parseFile(allocator, path)` - Parse TOML file into Value

### Value Access

- `value.get(key)` - Get value from table by key
- `value.at(index)` - Get value from array by index
- `value.getString()` - Get string value
- `value.getInteger()` - Get integer value
- `value.getFloat()` - Get float value
- `value.getBoolean()` - Get boolean value
- `value.getTable()` - Get table value
- `value.getArray()` - Get array value

### Serialization

- `ztoml.toString(allocator, value)` - Serialize Value to string

## Build

```bash
zig build
zig build test
```

## License

MIT
