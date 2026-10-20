# Decoding Kiwi

Read a Kiwi schema and decode messages against it, from untrusted input.

## Overview

Kiwi is Evan Wallace's schema-based binary format (github.com/evanw/kiwi): protobuf-like
varints, structs whose fields are always present, and messages whose fields are tagged and
optional. Figma's clipboard and `.fig` files carry their document as a Kiwi message, with
the binary schema that describes it embedded beside it. Woodcase's reader is generic: it
knows Kiwi, not Figma, and every definition it decodes comes from the schema it is handed.
Unwrapping a Figma payload — the container, its compression, mapping nodes — is a separate
layer above it.

```swift
let schema = try KiwiSchema(binary: schemaBytes)
let message = try schema.decode(messageBytes, as: "Message")
if case let .array(nodes)? = message["nodeChanges"] {
    for node in nodes {
        print(node["type"]?.enumName ?? "?", node["name"]?.stringValue ?? "")
    }
}
```

### The schema

A binary schema is a varint count of definitions, then each definition: a null-terminated
name, a kind byte (0 enum, 1 struct, 2 message) and its fields. Each field is a
null-terminated name, a zigzag type number — negative for one of the eight native types
(`bool`, `byte`, `int`, `uint`, `float`, `string`, `int64`, `uint64`, from −1 to −8), or
a definition's index — a flags byte whose bit 0 marks an array, and a varint value: an
enum case's value, a message field's id, a struct field's ordinal.

``KiwiSchema/init(binary:)`` reads that grammar into ``KiwiDefinition``s, resolving type
numbers to ``KiwiFieldType``s, then ``KiwiSchema/init(definitions:)`` compiles them.
Compiling refuses anything a decoder could not trust: duplicate names, duplicate field
values, a type that names nothing, and a struct that contains itself through non-array
fields, which has no finite encoding. Recursion through a message or an array is legal
Kiwi and allowed.

### Messages

Kiwi does not record which definition a buffer holds, so
``KiwiSchema/decode(_:as:maxDepth:)`` takes the root's name, as the reference
implementation's per-definition decoders do. A struct's fields are read in order; a
message's are read as id–value pairs until a zero id. The result is a ``KiwiRecord`` of
``KiwiValue``s: enums by case name, byte arrays as `Data`, structs and messages as nested
records. A message carries only the fields that were encoded, so a missing key means the
field was not sent.

Floats use Kiwi's own encoding: four little-endian bytes holding the IEEE bits rotated
left by nine, so the exponent byte comes first. A zero exponent byte stands alone — Kiwi's
writer stores zero and every denormal as the single byte `00` — and reads as zero. A 64-bit varint stops at nine bytes, the ninth carrying all eight
of its bits.

### Trusting nothing

A clipboard can be written by anyone, so every read assumes hostile input and fails with
a ``KiwiDecodingError`` rather than trapping:

- **Bounded counts.** Every count and length is checked against the bytes that remain
  before anything is allocated or looped over.
- **Bounded depth.** Each struct or message entered counts against `maxDepth`
  (``KiwiSchema/defaultMaxDepth`` by default), so a self-nesting message cannot exhaust
  the stack.
- **Strict varints.** A 32-bit varint whose fifth byte still continues is malformed.
- **Exact ends.** A schema and a decoded root must end where their input does. The
  reference implementation ignores trailing bytes; Woodcase treats them as a sign the
  wrong root or the wrong bytes were chosen.
- **Unknown values are errors.** A message field id or enum value that the schema does
  not declare fails with its offset, as the reference implementation's decoders do.

Strings that are not valid UTF-8 decode with replacement characters rather than failing,
so text from a lenient encoder still reads.

## Topics

### Schemas

- ``KiwiSchema``
- ``KiwiDefinition``
- ``KiwiField``
- ``KiwiFieldType``

### Decoded Values

- ``KiwiRecord``
- ``KiwiValue``

### Reading Bytes

- ``KiwiByteReader``
- ``KiwiDecodingError``
