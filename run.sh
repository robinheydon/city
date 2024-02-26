#!/bin/sh
zig build --color on --summary all || exit 1
zig-out/bin/city
