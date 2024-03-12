#!/bin/sh
zig build --color on --summary all -freference-trace=32 test
