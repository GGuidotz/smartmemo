#!/usr/bin/env python3
"""Controllo di sintassi Swift senza compilatore (nel cloud Swift non c'è): segnala i nodi ERROR e MISSING di
tree-sitter-swift. Non sostituisce la compilazione: tipi e API li controlla solo swiftc sul Mac.
    pip install tree-sitter tree-sitter-swift
    python3 -I tools/check-syntax.py
"""
import os, sys
import tree_sitter_swift
from tree_sitter import Language, Parser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
parser = Parser(Language(tree_sitter_swift.language()))
bad = 0
for base, _, files in os.walk(os.path.join(ROOT, "Sources")):
    for name in sorted(files):
        if not name.endswith(".swift"):
            continue
        path = os.path.join(base, name)
        src = open(path, "rb").read()
        tree = parser.parse(src)
        stack = [tree.root_node]
        while stack:
            n = stack.pop()
            if n.type == "ERROR" or n.is_missing:
                line = n.start_point[0] + 1
                text = src.splitlines()[n.start_point[0]].decode("utf-8", "replace").strip()
                print(f"{os.path.relpath(path, ROOT)}:{line}: {'manca ' + n.type if n.is_missing else 'errore'}: {text[:100]}")
                bad += 1
                continue
            stack.extend(n.children)
print(f"{bad} problemi")
sys.exit(1 if bad else 0)
