TARGET=target
EXE=ip-neighbor-notifications

default: build

build:
	stack build
	hlint src

clean:
	stack clean
	rm -rf $(TARGET)

build-static:
	mkdir -p $(TARGET)
	stack --local-bin-path $(TARGET) install $(STACK_OPTS) $(EXE)
	upx $(TARGET)/$(EXE)


.PHONY: \
	build \
	clean \
	default



