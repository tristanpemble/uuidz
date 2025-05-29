# sqlite3-uuidz

A SQLite extension providing comprehensive UUID functionality. Existing solutions lacked support for some UUID versions, had reliability issues, or default
to TEXT representations instead of BLOB, which is annoying and wrong. Written in Zig as a thin wrapper around [libuuid](https://github.com/util-linux/util-linux/tree/master/libuuid).

## Disclaimer

This project was written largely with the assistance of a large language model. While the code has been tested and reviewed, please use it with appropriate caution and testing in your own projects. If/when this project reaches more review and usage, and I have more confidence in it I will remove this disclaimer.
For now, it was written to get my hobby project unblocked.

## Building

### Nix

Requires flakes to be enabled.

```
nix build github:tristanpemble/sqlite3-uuidz
```

### Zig

Requires `libsqlite3` and `libuuid` to be installed on your system.

```
zig build
```

## Reference

```sqlite
-- UUID Generation
SELECT uuid_v1();
SELECT uuid_v3(uuid_parse('6ba7b810-9dad-11d1-80b4-00c04fd430c8'), 'example.com');
SELECT uuid_v4();
SELECT uuid_v5(uuid_parse('6ba7b811-9dad-11d1-80b4-00c04fd430c8'), 'https://example.com');
SELECT uuid_v6();
SELECT uuid_v7();

-- UUID Conversion
SELECT uuid_format(uuid_v4());
SELECT uuid_parse('550e8400-e29b-41d4-a716-446655440000');

-- UUID Metadata
SELECT uuid_version(uuid_v4());
SELECT uuid_variant(uuid_v4());
SELECT uuid_timestamp(uuid_v1());
SELECT uuid_timestamp(uuid_v7());
SELECT datetime(uuid_timestamp(uuid_v7()), 'unixepoch');
```

Or, to demonstrate a couple of usecases:

```sqlite
CREATE TABLE users (
    id          BLOB PRIMARY KEY DEFAULT (uuid_v7()),
    display_id  TEXT GENERATED ALWAYS AS (uuid_format(id)) VIRTUAL,
    name        TEXT,
    CHECK (uuid_version(id) == 7)
);
```

## License

MIT
