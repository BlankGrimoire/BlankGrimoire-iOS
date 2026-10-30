# BlankGrimoire iOS — Makefile

# Configuration
SDK_REPO_PATH ?= ../BlankGrimoire-sdk
SDK_VERSION_FILE = .sdk-version
SDK_RELEASE_URL = https://github.com/BlankGrimoire/BlankGrimoire-sdk/releases/download

# Project
PROJECT_YML = project.yml
XCODE_PROJECT = BlankGrimoire.xcodeproj

# Swift
SWIFT_FORMAT = swift format
SWIFT_FORMAT_CONFIG = .swift-format
SWIFT_TEST = swift test

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

.PHONY: help generate build test format lint sync-sdk clean

help:
	@echo "$(GREEN)BlankGrimoire iOS Makefile$(NC)"
	@echo ""
	@echo "Usage:"
	@echo "  make generate      Generate Xcode project with xcodegen"
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

generate: $(XCODE_PROJECT)

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
	\
	# Copy runtime.js
	mkdir -p BlankGrimoire/Resources/Runtime; \
	cp $(SDK_REPO_PATH)/packages/runtime/dist/runtime.js BlankGrimoire/Resources/Runtime/runtime.js; \
	echo "$(GREEN)Copied runtime.js$(NC)"; \
	\
	# Copy schema
	cp $(SDK_REPO_PATH)/schema/v1.json BlankGrimoire/Resources/Contract/schema-v1.json; \
	echo "$(GREEN)Copied schema-v1.json$(NC)"; \
	\
	# Copy fixtures
	rm -rf BlankGrimoire/Resources/Contract/fixtures; \
	mkdir -p BlankGrimoire/Resources/Contract/fixtures; \
	cp -r $(SDK_REPO_PATH)/fixtures/v1 BlankGrimoire/Resources/Contract/fixtures/v1; \
	echo "$(GREEN)Copied fixtures/v1/$(NC)"; \
	\
	@echo "$(GREEN)SDK sync complete! Version $$SDK_VERSION saved to $(SDK_VERSION_FILE)$(NC)"

sync-sdk-release:
	@echo "$(GREEN)Syncing SDK from GitHub release...$(NC)"
	@if [ ! -f $(SDK_VERSION_FILE) ]; then \
		echo "$(RED).sdk-version file not found$(NC)"; \
		exit 1; \
	fi
	@SDK_VERSION=$$(cat $(SDK_VERSION_FILE)); \
	echo "$(GREEN)SDK version from .sdk-version: $$SDK_VERSION$(NC)"; \
	\
	RELEASE_URL="$(SDK_RELEASE_URL)/v$$SDK_VERSION"; \
	TEMP_DIR=$$(mktemp -d); \
	\
	echo "$(YELLOW)Downloading runtime.js...$(NC)"; \
	curl -L "$$RELEASE_URL/runtime.js" -o "$$TEMP_DIR/runtime.js" || { echo "$(RED)Failed to download runtime.js$(NC)"; exit 1; }; \
	mkdir -p BlankGrimoire/Resources/Runtime; \
	cp "$$TEMP_DIR/runtime.js" BlankGrimoire/Resources/Runtime/runtime.js; \
	\
	echo "$(YELLOW)Downloading schema-v1.json...$(NC)"; \
	curl -L "$$RELEASE_URL/schema-v1.json" -o "$$TEMP_DIR/schema-v1.json" || { echo "$(RED)Failed to download schema-v1.json$(NC)"; exit 1; }; \
	mkdir -p BlankGrimoire/Resources/Contract; \
	cp "$$TEMP_DIR/schema-v1.json" BlankGrimoire/Resources/Contract/schema-v1.json; \
	\
	echo "$(YELLOW)Downloading fixtures-v1.tar.gz...$(NC)"; \
	curl -L "$$RELEASE_URL/fixtures-v1.tar.gz" -o "$$TEMP_DIR/fixtures-v1.tar.gz" || { echo "$(RED)Failed to download fixtures-v1.tar.gz$(NC)"; exit 1; }; \
	rm -rf BlankGrimoire/Resources/Contract/fixtures; \
	mkdir -p BlankGrimoire/Resources/Contract/fixtures; \
	tar -xzf "$$TEMP_DIR/fixtures-v1.tar.gz" -C BlankGrimoire/Resources/Contract/fixtures; \
	\
	rm -rf "$$TEMP_DIR"; \
	echo "$(GREEN)SDK release sync complete!$(NC)"

# Strip extended attributes that cause code signing issues on macOS
clean-xattrs:
	@echo "$(YELLOW)Cleaning extended attributes...$(NC)"
	@find Packages/ReaderCore/.build -name "*.xctest" -exec xattr -cr {} \; 2>/dev/null || true

# ReaderCore package tests
test-readercore: clean-xattrs
	@echo "$(GREEN)Running ReaderCore package tests...$(NC)"
	@cd Packages/ReaderCore && xattr -cr .build/out/Products/Debug/ReaderCoreTests.xctest 2>/dev/null; swift test

# Clean
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(XCODE_PROJECT)
	rm -rf .build
	rm -rf DerivedData
	rm -rf BlankGrimoire/Resources/Runtime
	rm -rf BlankGrimoire/Resources/Contract

# CI
ci: generate test lint
	@echo "$(GREEN)CI pipeline complete!$(NC)"