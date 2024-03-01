#!/bin/sh
zig build -Doptimize=ReleaseSmall --color on --summary all || exit 1
zig-out/bin/city

