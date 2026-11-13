#!/bin/zsh
# Prova la logica di Sources/Core (elenchi, regole di scrittura, controllo della punteggiatura) senza l'app.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
swiftc -swift-version 5 -module-cache-path "${TMPDIR:-/tmp}/smartmemo-modcache" Sources/Core/*.swift Tests/main.swift -o build/core-tests
build/core-tests
