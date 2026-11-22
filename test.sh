#!/bin/bash
# Chạy bộ test tự động (không cần remote, không di chuột / cuộn thật).
# Dùng:  ./test.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
SRC=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -Onone -target "$(uname -m)-apple-macos13" $SRC Tests/*.swift -o build/tests
./build/tests
