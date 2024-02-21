#!/bin/sh
zig build || exit 1
valgrind zig-out/bin/city

