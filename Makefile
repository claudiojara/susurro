PACKAGES := SusurroCore SusurroPlatform SusurroInference SusurroUI SusurroFeatures
PROJECT := App/Susurro.xcodeproj
DERIVED_DATA := build
APP := $(DERIVED_DATA)/Build/Products/Debug/Susurro.app

# RECORD=1 re-records snapshot references. Do it only on the CI image (record-snapshots workflow).
SNAPSHOT_ENV := $(if $(RECORD),SNAPSHOT_TESTING_RECORD=all)

.PHONY: bootstrap format lint test snapshots build run clean

bootstrap:
	@command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }
	xcodegen generate --spec App/project.yml

format:
	xcrun swift-format format --in-place --recursive Packages App

lint:
	xcrun swift-format lint --strict --recursive Packages App

test:
	@for pkg in $(PACKAGES); do \
		echo "==> swift test: $$pkg"; \
		swift test --package-path Packages/$$pkg --skip Snapshot || exit 1; \
	done

# Stub until the snapshot infrastructure lands. It will run: $(SNAPSHOT_ENV) swift test --filter Snapshot
snapshots:
	@echo "No snapshot suites yet."

build: bootstrap
	xcodebuild build -project $(PROJECT) -scheme Susurro -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA)

run: build
	open $(APP)

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT) Packages/*/.build
