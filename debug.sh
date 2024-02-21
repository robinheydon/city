#!/bin/sh
zig build || exit 1
lldb zig-out/bin/city

