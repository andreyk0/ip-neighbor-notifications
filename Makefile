default: build

build:
	stack build
	hlint src

clean:
	stack clean


.PHONY: \
	build \
	clean \
	default
