# zlib

This is [zlib](https://www.zlib.net/),
packaged for [Zig](https://ziglang.org/).

## How to use it

First, update your `build.zig.zon`:

```
zig fetch --save https://github.com/allyourcodebase/zlib/archive/refs/tags/1.3.1.tar.gz
```

Next, add this snippet to your `build.zig` script:

```zig
const zlib_dep = b.dependency("zlib", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.linkLibrary(zlib_dep.artifact("z"));
```

This will provide zlib as a static library to `your_compilation`.
