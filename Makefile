.PHONY: lint
lint:
	@./type_check.sh

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
	cd deps; git clone --depth 1 https://github.com/kdheepak/panvimdoc.git
	sed -i.bak "s/\r$$//" deps/panvimdoc/panvimdoc.sh

.PHONY: deps
deps-clean:
	rm -rf deps
