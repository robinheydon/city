#!/bin/sh
zig build || exit 1
zig-out/bin/city
