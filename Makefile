# BlankGrimoire iOS — Makefile

# Configuration
SDK_REPO_PATH ?= ../BlankGrimoire-sdk
SDK_VERSION_FILE = .sdk-version
SDK_RELEASE_URL = https://github.com/BlankGrimoire/BlankGrimoire-sdk/releases/download

# Vendored SDK assets
RUNTIME_JS = Packages/ReaderCore/Sources/ReaderCore/PluginEngine/Runtime/Resources/runtime.js
TEST_FIXTURES = Packages/ReaderCore/Tests/ReaderCoreTests/Resources/Contract/fixtures
SDK_ASSETS_SUMS = sdk-assets.sha256

# Project
PROJECT_YML = project.yml
XCODE_PROJECT = BlankGrimoire.xcodeproj

# Swift
SWIFT_FORMAT = swift format
SWIFT_FORMAT_CONFIG = .swift-format
SWIFT_TEST = swift test
SWIFT_TEST_FLAGS ?=

# Build ReaderCore tests outside iCloud by default. macOS attaches
# com.apple.fileprovider.* / FinderInfo xattrs to directories under
# ~/Documents, which makes codesign fail on the test resource bundle.
READERCORE_SCRATCH ?= $(HOME)/Library/Caches/BlankGrimoire/ReaderCoreBuild

# XcodeGen
XCODEGEN = xcodegen

# xcodebuild
XCODEBUILD = xcodebuild
SCHEME = BlankGrimoire
# Pick the first available iPhone simulator instead of hardcoding a model that
# depends on the installed Xcode version.
DEFAULT_SIMULATOR := $(shell bash scripts/default-simulator.sh 2>/dev/null)
DESTINATION ?= platform=iOS Simulator,name=$(DEFAULT_SIMULATOR)

# SDK version declared by the SDK repository. Prefer a JSON parser over
# grep/sed so formatting changes in package.json cannot corrupt the version.
SDK_PACKAGE_VERSION := $(shell node -p "require(require('path').resolve('$(SDK_REPO_PATH)', 'package.json')).version" 2>/dev/null)
# The vendored pin is explicit: syncing local assets never changes it unless
# the caller passes SDK_VERSION=<version> on the command line.
SDK_VERSION ?= $(shell cat $(SDK_VERSION_FILE) 2>/dev/null)

# Colors
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m

.PHONY: help gen generate build test format lint sync-sdk sync-sdk-release \
	verify-sdk update-sdk-assets clean clean-xattrs test-readercore ci

help:
	@echo "$(GREEN)BlankGrimoire iOS Makefile$(NC)"
	@echo ""
	@echo "Usage:"
	@echo "  make gen           Generate Xcode project with xcodegen (alias: generate)"
	@echo "  make build         Build app for simulator"
	@echo "  make test          Run app unit tests"
	@echo "  make test-readercore  Run ReaderCore package tests"
	@echo "  make format        Format code with swift-format"
	@echo "  make lint          Lint code with swift-format"
	@echo "  make verify-sdk    Verify vendored SDK assets against $(SDK_ASSETS_SUMS)"
	@echo "  make sync-sdk      Sync SDK from local repo (SDK_REPO_PATH=../BlankGrimoire-sdk)"
	@echo "  make sync-sdk-release  Sync SDK from GitHub release (uses .sdk-version)"
	@echo "  make clean         Clean build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  SDK_REPO_PATH      Path to SDK repo (default: ../BlankGrimoire-sdk)"
	@echo "  SDK_VERSION        Version to pin in .sdk-version (default: current pin)"
	@echo "  SCHEME             Xcode scheme (default: BlankGrimoire)"
	@echo "  DESTINATION        Simulator destination (default: first available iPhone)"
	@echo "  SWIFT_TEST_FLAGS   Extra flags for swift test"
	@echo "  READERCORE_SCRATCH SwiftPM scratch path (default: ~/Library/Caches/BlankGrimoire/ReaderCoreBuild)"

generate: $(XCODE_PROJECT)

gen: generate

$(XCODE_PROJECT): $(PROJECT_YML) Packages/ReaderCore/Package.swift
	@echo "$(GREEN)Generating Xcode project...$(NC)"
	$(XCODEGEN) generate --spec $(PROJECT_YML)

build: generate
	@echo "$(GREEN)Building $(SCHEME) for $(DESTINATION)...$(NC)"
	$(XCODEBUILD) build \
		-project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES

test: generate
	@echo "$(GREEN)Running app tests...$(NC)"
	$(XCODEBUILD) test \
		-project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO

format:
	@echo "$(GREEN)Formatting code...$(NC)"
	$(SWIFT_FORMAT) format --configuration $(SWIFT_FORMAT_CONFIG) --recursive --in-place .

lint:
	@echo "$(GREEN)Linting code...$(NC)"
	$(SWIFT_FORMAT) lint --configuration $(SWIFT_FORMAT_CONFIG) --recursive .

verify-sdk:
	@echo "$(GREEN)Verifying vendored SDK assets...$(NC)"
	@bash scripts/verify-sdk-assets.sh

update-sdk-assets:
	@bash scripts/update-sdk-assets.sh

# SDK Synchronization
sync-sdk:
	@echo "$(GREEN)Syncing SDK from $(SDK_REPO_PATH)...$(NC)"
	@if [ ! -d "$(SDK_REPO_PATH)" ]; then \
		echo "$(RED)SDK repo not found at $(SDK_REPO_PATH)$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SDK_VERSION)" ]; then \
		echo "$(RED)Unable to determine the SDK version; pass SDK_VERSION=<version>$(NC)"; \
		exit 1; \
	fi
	@if [ -n "$(SDK_PACKAGE_VERSION)" ] && [ "$(SDK_PACKAGE_VERSION)" != "$(SDK_VERSION)" ]; then \
		echo "$(YELLOW)Warning: SDK package.json declares $(SDK_PACKAGE_VERSION); keeping pinned $(SDK_VERSION)$(NC)"; \
	fi
	@echo "$(SDK_VERSION)" > $(SDK_VERSION_FILE)
	@echo "$(GREEN)SDK version: $(SDK_VERSION)$(NC)"
	@mkdir -p $(dir $(RUNTIME_JS))
	@cp $(SDK_REPO_PATH)/packages/runtime/dist/runtime.js $(RUNTIME_JS)
	@echo "$(GREEN)Copied runtime.js to ReaderCore$(NC)"
	@rm -rf $(TEST_FIXTURES)
	@mkdir -p $(TEST_FIXTURES)
	@cp -R $(SDK_REPO_PATH)/fixtures/v1 $(TEST_FIXTURES)/
	@echo "$(GREEN)Copied fixtures/v1 to ReaderCore tests$(NC)"
	@bash scripts/update-sdk-assets.sh
	@echo "$(GREEN)SDK sync complete! Version $(SDK_VERSION) saved to $(SDK_VERSION_FILE)$(NC)"

sync-sdk-release:
	@echo "$(GREEN)Syncing SDK from GitHub release...$(NC)"
	@if [ ! -f $(SDK_VERSION_FILE) ]; then \
		echo "$(RED).sdk-version file not found$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f $(SDK_ASSETS_SUMS) ]; then \
		echo "$(RED)$(SDK_ASSETS_SUMS) not found; run make sync-sdk first$(NC)"; \
		exit 1; \
	fi
	@SDK_VERSION=$$(cat $(SDK_VERSION_FILE)); \
	echo "$(GREEN)SDK version from .sdk-version: $$SDK_VERSION$(NC)"; \
	RELEASE_URL="$(SDK_RELEASE_URL)/v$$SDK_VERSION"; \
	TEMP_DIR=$$(mktemp -d); \
	trap 'rm -rf "$$TEMP_DIR"' EXIT; \
	STAGE="$$TEMP_DIR/stage"; \
	mkdir -p "$$STAGE/$$(dirname $(RUNTIME_JS))" "$$STAGE/$(TEST_FIXTURES)"; \
	echo "$(YELLOW)Downloading runtime.js...$(NC)"; \
	curl -fsSL --retry 3 "$$RELEASE_URL/runtime.js" -o "$$STAGE/$(RUNTIME_JS)" || { echo "$(RED)Failed to download runtime.js$(NC)"; exit 1; }; \
	echo "$(YELLOW)Downloading fixtures-v1.tar.gz...$(NC)"; \
	curl -fsSL --retry 3 "$$RELEASE_URL/fixtures-v1.tar.gz" -o "$$TEMP_DIR/fixtures-v1.tar.gz" || { echo "$(RED)Failed to download fixtures-v1.tar.gz$(NC)"; exit 1; }; \
	tar -xzf "$$TEMP_DIR/fixtures-v1.tar.gz" -C "$$STAGE/$(TEST_FIXTURES)" || { echo "$(RED)Failed to extract fixtures-v1.tar.gz$(NC)"; exit 1; }; \
	cp $(SDK_VERSION_FILE) $(SDK_ASSETS_SUMS) "$$STAGE/"; \
	echo "$(YELLOW)Verifying downloaded assets...$(NC)"; \
	bash scripts/verify-sdk-assets.sh "$$STAGE" || { echo "$(RED)Downloaded SDK assets do not match $(SDK_ASSETS_SUMS)$(NC)"; exit 1; }; \
	rm -rf $(TEST_FIXTURES); \
	mkdir -p "$$(dirname $(RUNTIME_JS))" "$(TEST_FIXTURES)"; \
	cp "$$STAGE/$(RUNTIME_JS)" $(RUNTIME_JS); \
	cp -R "$$STAGE/$(TEST_FIXTURES)/." "$(TEST_FIXTURES)/"; \
	echo "$(GREEN)SDK release sync complete!$(NC)"

# Strip extended attributes that cause code signing issues on macOS. This is a
# fallback for an existing in-repo .build; the supported fix is READERCORE_SCRATCH.
clean-xattrs:
	@echo "$(YELLOW)Cleaning extended attributes...$(NC)"
	@find Packages/ReaderCore/.build \( -name "*.xctest" -o -name "*.bundle" \) \
		-exec xattr -cr {} \; 2>/dev/null || true

# ReaderCore package tests. The scratch path defaults outside iCloud and can be
# overridden with READERCORE_SCRATCH=/path. Do not use Packages/ReaderCore/.build
# under ~/Documents: codesign fails with "resource fork, Finder information, or
# similar detritus not allowed". That is a local xattr problem, not a CI-only
# SwiftPM limitation.
test-readercore: clean-xattrs
	@echo "$(GREEN)Running ReaderCore package tests...$(NC)"
	@mkdir -p $(READERCORE_SCRATCH)
	@cd Packages/ReaderCore && $(SWIFT_TEST) --scratch-path $(READERCORE_SCRATCH) $(SWIFT_TEST_FLAGS)

# Clean
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(XCODE_PROJECT)
	rm -rf .build
	rm -rf DerivedData
	rm -rf build
	rm -rf release
	rm -rf "$(READERCORE_SCRATCH)"

# CI
ci: verify-sdk lint test-readercore test build
	@echo "$(GREEN)CI pipeline complete!$(NC)"
