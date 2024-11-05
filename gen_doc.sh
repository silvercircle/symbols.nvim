#!/usr/bin/env bash

../panvimdoc/panvimdoc_unix.sh \
    --project-name "symbols" \
    --vim-version "NVIM v0.10.0" \
    --input-file README.md \
    --treesitter true \
    --toc true

sed -i "" "1,2d" ./doc/symbols.txt
