#!/bin/sh
zig build --color on -freference-trace=32 || exit 1
zig-out/bin/city
