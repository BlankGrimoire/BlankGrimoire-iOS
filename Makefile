# BlankGrimoire iOS — Makefile

# Configuration
SDK_REPO_PATH ?= ../BlankGrimoire-sdk
SDK_VERSION_FILE = .sdk-version
SDK_RELEASE_URL = https://github.com/BlankGrimoire/BlankGrimoire-sdk/releases/download

# Vendored SDK assets
RUNTIME_JS = Packages/ReaderCore/Sources/ReaderCore/PluginEngine/Runtime/Resources/runtime.js
TEST_FIXTURES = Packages/ReaderCore/Tests/ReaderCoreTests/Resources/Contract/fixtures

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
DESTINATION ?= platform=iOS Simulator,name=iPhone 17

# Colors
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m

.PHONY: help gen generate build test format lint sync-sdk sync-sdk-release clean clean-xattrs test-readercore

help:
	@echo "$(GREEN)BlankGrimoire iOS Makefile$(NC)"
	@echo ""
	@echo "Usage:"
	@echo "  make gen           Generate Xcode project with xcodegen (alias: generate)"
	@echo "  make build         Build app for simulator"
	@echo "  make test          Run unit tests"
	@echo "  make format        Format code with swift-format"
	@echo "  make lint          Lint code with swift-format"
	@echo "  make sync-sdk      Sync SDK from local repo (SDK_REPO_PATH=../BlankGrimoire-sdk)"
	@echo "  make sync-sdk-release  Sync SDK from GitHub release (uses .sdk-version)"
	@echo "  make clean         Clean build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  SDK_REPO_PATH      Path to SDK repo (default: ../BlankGrimoire-sdk)"
	@echo "  SCHEME             Xcode scheme (default: BlankGrimoire)"
	@echo "  DESTINATION        Simulator destination (default: iPhone 17)"
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
	@echo "$(GREEN)Running tests...$(NC)"
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

# SDK Synchronization
sync-sdk:
	@echo "$(GREEN)Syncing SDK from $(SDK_REPO_PATH)...$(NC)"
	@if [ ! -d "$(SDK_REPO_PATH)" ]; then \
		echo "$(RED)SDK repo not found at $(SDK_REPO_PATH)$(NC)"; \
		exit 1; \
	fi
	@SDK_VERSION=$$(cat $(SDK_REPO_PATH)/package.json | grep '"version"' | head -1 | sed 's/.*"version": "\(.*\)".*/\1/'); \
	echo "$$SDK_VERSION" > $(SDK_VERSION_FILE); \
	echo "$(GREEN)SDK version: $$SDK_VERSION$(NC)"; \
	mkdir -p Packages/ReaderCore/Sources/ReaderCore/PluginEngine/Runtime/Resources; \
	cp $(SDK_REPO_PATH)/packages/runtime/dist/runtime.js $(RUNTIME_JS); \
	echo "$(GREEN)Copied runtime.js to ReaderCore$(NC)"; \
	rm -rf $(TEST_FIXTURES); \
	mkdir -p $(TEST_FIXTURES); \
	cp -r $(SDK_REPO_PATH)/fixtures/v1 $(TEST_FIXTURES)/v1; \
	echo "$(GREEN)Copied fixtures/v1 to ReaderCore tests$(NC)"; \
	echo "$(GREEN)SDK sync complete! Version $$SDK_VERSION saved to $(SDK_VERSION_FILE)$(NC)"

sync-sdk-release:
	@echo "$(GREEN)Syncing SDK from GitHub release...$(NC)"
	@if [ ! -f $(SDK_VERSION_FILE) ]; then \
		echo "$(RED).sdk-version file not found$(NC)"; \
		exit 1; \
	fi
	@SDK_VERSION=$$(cat $(SDK_VERSION_FILE)); \
	echo "$(GREEN)SDK version from .sdk-version: $$SDK_VERSION$(NC)"; \
	RELEASE_URL="$(SDK_RELEASE_URL)/v$$SDK_VERSION"; \
	TEMP_DIR=$$(mktemp -d); \
	echo "$(YELLOW)Downloading runtime.js...$(NC)"; \
	curl -L "$$RELEASE_URL/runtime.js" -o "$$TEMP_DIR/runtime.js" || { echo "$(RED)Failed to download runtime.js$(NC)"; exit 1; }; \
	mkdir -p Packages/ReaderCore/Sources/ReaderCore/PluginEngine/Runtime/Resources; \
	cp "$$TEMP_DIR/runtime.js" $(RUNTIME_JS); \
	echo "$(YELLOW)Downloading fixtures-v1.tar.gz...$(NC)"; \
	curl -L "$$RELEASE_URL/fixtures-v1.tar.gz" -o "$$TEMP_DIR/fixtures-v1.tar.gz" || { echo "$(RED)Failed to download fixtures-v1.tar.gz$(NC)"; exit 1; }; \
	rm -rf $(TEST_FIXTURES); \
	mkdir -p $(TEST_FIXTURES); \
	tar -xzf "$$TEMP_DIR/fixtures-v1.tar.gz" -C $(TEST_FIXTURES); \
	rm -rf "$$TEMP_DIR"; \
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
	rm -rf BlankGrimoire/Resources

# CI
ci: generate test lint
	@echo "$(GREEN)CI pipeline complete!$(NC)"