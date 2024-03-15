#!/bin/sh
zig build || exit 1
valgrind --gen-suppressions=all --suppressions=valgrind.suppressions zig-out/bin/city

