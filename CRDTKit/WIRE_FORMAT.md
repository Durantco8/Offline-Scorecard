# Wire Format — CBOR Schema

All transport payloads are encoded as [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949).
A second implementation can be built against this spec without reading the Swift source.

## Conventions

- **UUID**: CBOR byte string, 16 bytes, big-endian RFC 4122 layout.
- **Map with integer keys**: CBOR map where keys are unsigned integers (field IDs).
- **Nullable**: encoded as the value or CBOR `null` (0xf6).

## Primitive types

### DeviceID

CBOR byte string (16 bytes) — the raw UUID.

### PlayerID

Same encoding as DeviceID.

### Dot

CBOR array of 2 elements:

| Index | Type | Description |
|-------|------|-------------|
| 0 | bytes(16) | DeviceID |
| 1 | unsigned | Counter |

### HLC (Hybrid Logical Clock)

CBOR array of 3 elements:

| Index | Type | Description |
|-------|------|-------------|
| 0 | unsigned | Wall clock (ms since Unix epoch) |
| 1 | unsigned | Logical counter |
| 2 | bytes(16) | DeviceID |

### VersionVector

CBOR map: `{ DeviceID → unsigned }`. Keys are 16-byte UUID byte strings,
values are the highest known counter for that device.

## Domain types

### Lie

CBOR unsigned integer:

| Value | Meaning |
|-------|---------|
| 0 | tee |
| 1 | fairway |
| 2 | rough |
| 3 | sand |
| 4 | green |
| 5 | recovery |

### Shot

CBOR array of 4 elements:

| Index | Type | Description |
|-------|------|-------------|
| 0 | unsigned | Start lie (Lie enum) |
| 1 | float64 | Start distance to pin (yards) |
| 2 | unsigned | End lie (Lie enum) |
| 3 | float64 | End distance to pin (yards) |

### Hole

CBOR array of 3 elements:

| Index | Type | Description |
|-------|------|-------------|
| 0 | unsigned | Hole number (1–18) |
| 1 | unsigned | Par |
| 2 | unsigned | Stroke index |

### Course

CBOR array of Hole.

### HoleEntry

CBOR map with integer keys:

| Key | Type | Description |
|-----|------|-------------|
| 0 | unsigned | Stroke count |
| 1 | array(Shot) \| null | Shots (null in v1) |

## CRDT types

### LWWRegister\<T\>

CBOR map with integer keys:

| Key | Type | Description |
|-----|------|-------------|
| 0 | T | Current value |
| 1 | HLC | Timestamp of the winning write |
| 2 | Dot | Write dot (for delta computation) |

### MVRegister\<T\>

CBOR map with integer keys:

| Key | Type | Description |
|-----|------|-------------|
| 0 | array | Entries: each is `[T, Dot]` |
| 1 | VersionVector | Observed version vector |

### ORSet\<T\>

CBOR map with integer keys:

| Key | Type | Description |
|-----|------|-------------|
| 0 | array | Entries: each is `[T, Dot]` |
| 1 | VersionVector | Observed version vector |

## Transport payload

### RoundDelta

The top-level payload sent over the `Transport` protocol.

CBOR map with integer keys:

| Key | Type | Description |
|-----|------|-------------|
| 0 | bytes(16) | Round ID (UUID) |
| 1 | LWWRegister\<Course\> \| null | Course delta |
| 2 | ORSet\<PlayerID\> \| null | Players delta |
| 3 | map { PlayerID → LWWRegister\<String\> } | Changed player names |
| 4 | map { PlayerID → map { unsigned → MVRegister\<HoleEntry\> } } | Changed score entries |
| 5 | unsigned | Schema version (currently 1) |

Keys 3 and 4 use PlayerID (16-byte UUID) as map keys. Key 4's inner map uses
unsigned hole numbers (1–18) as keys.

Null fields (keys 1, 2) indicate no change for that component. Empty maps
(keys 3, 4) indicate no name or score changes.

## Merge semantics

A `RoundDelta` is a valid CRDT state fragment. The receiver merges each
non-null field using the standard merge for that CRDT type:

- **LWWRegister**: higher HLC wins.
- **MVRegister**: dot-kernel merge — an entry survives if it appears in both
  sides or its dot is not covered by the other side's version vector.
- **ORSet**: same dot-kernel merge as MVRegister; effect is add-wins over
  concurrent remove.
- **VersionVector**: pointwise max.
