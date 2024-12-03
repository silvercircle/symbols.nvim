.PHONY: lint
lint:
	@./type_check.sh

.PHONY: test
test:
	# Before running the tests for the first time, open Neovim with the following command
	# to allow it to install all the Treesitter parsers: nvim -u tests/nvim_test/init.lua
	@nvim --headless --noplugin -u tests/nvim_tester/init.lua -c "lua MiniTest.run()"

.PHONY: gen-docs
docs:
	@deps/panvimdoc/panvimdoc.sh \
		--project-name "symbols" \
		--vim-version "NVIM v0.10.0" \
		--input-file README.md \
		--treesitter true \
		--toc true
	@sed -i "" "1,2d" ./doc/symbols.txt

.PHONY: deps
deps:
	mkdir -p deps
	# panvimdoc
	cd deps; git clone --depth 1 https://github.com/kdheepak/panvimdoc.git
	sed -i.bak "s/\r$$//" deps/panvimdoc/panvimdoc.sh
	# treesitter
	cd deps; git clone --depth 1 https://github.com/nvim-treesitter/nvim-treesitter.git

.PHONY: deps
deps-clean:
	rm -rf deps
