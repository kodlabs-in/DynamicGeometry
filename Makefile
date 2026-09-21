.PHONY: check format lint release-check test

SWIFT_TEST_FLAGS ?=

check: lint test

release-check: check
	swift build --configuration release

format:
	swift format --in-place --recursive --configuration .swift-format Package.swift Sources Tests

lint:
	swift format lint --recursive --configuration .swift-format Package.swift Sources Tests
	swiftlint lint --no-cache --strict --config .swiftlint.yml

test:
	SWIFTPM_MODULECACHE_OVERRIDE=$(CURDIR)/.cache/swiftpm-module-cache \
	CLANG_MODULE_CACHE_PATH=$(CURDIR)/.cache/clang-module-cache \
	swift test $(SWIFT_TEST_FLAGS)
