#!/bin/sh
zig build -Dtarget=x86_64-windows -freference-trace=32 --color on --summary all
