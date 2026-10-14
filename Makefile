PACKAGES := SusurroCore SusurroPlatform SusurroInference SusurroUI SusurroFeatures
PROJECT := App/Susurro.xcodeproj
DERIVED_DATA := build
APP := $(DERIVED_DATA)/Build/Products/Debug/Susurro.app
APP_ID := dev.claudiojara.susurro

# SwiftPM looks up github.com credentials in the keychain before it downloads a binary artifact, as FluidAudio's
# dependency does. With several github.com entries that lookup stalled the build, and no dependency needs credentials.
SWIFTPM_FLAGS := --disable-keychain

# xcodebuild resolves the same binary artifact by itself and has no way to skip the keychain: on a Mac with several
# github.com entries it stalls on the lookup, which waits for a keychain prompt that nobody sees. So SwiftPM resolves the
# packages first, without the keychain, into a folder that xcodebuild is then told to use as it is.
SOURCE_PACKAGES := $(DERIVED_DATA)/SourcePackages
XCODEBUILD_PACKAGE_FLAGS := -clonedSourcePackagesDirPath $(SOURCE_PACKAGES) -disableAutomaticPackageResolution

# RECORD=1 re-records snapshot references. Do it only on the CI image (record-snapshots workflow). Without it nothing is
# ever written: a missing reference fails the test and creates no file.
SNAPSHOT_ENV := SNAPSHOT_TESTING_RECORD=$(if $(RECORD),all,never)

.PHONY: bootstrap resolve format lint test snapshots build run clean

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
		swift test $(SWIFTPM_FLAGS) --package-path Packages/$$pkg --skip Snapshot || exit 1; \
	done

# The snapshot suites (the ones with Snapshot in their name, which `make test` skips) compare pictures of the views with
# the references in __Snapshots__. The pictures differ a little between macOS versions, so a run on another machine than
# the CI image can fail. With RECORD=1 every test fails on purpose, because that is how recording reports itself; the
# record-snapshots workflow then runs the target again without it.
snapshots:
	$(SNAPSHOT_ENV) swift test $(SWIFTPM_FLAGS) --package-path Packages/SusurroUI --filter Snapshot

# The pins are in Packages/SusurroFeatures/Package.resolved, the package the app depends on.
resolve:
	swift package $(SWIFTPM_FLAGS) --package-path Packages/SusurroFeatures --scratch-path $(SOURCE_PACKAGES) resolve

build: bootstrap resolve
	xcodebuild build -project $(PROJECT) -scheme Susurro -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) $(XCODEBUILD_PACKAGE_FLAGS)

# Builds the app and starts it, replacing a copy that is already running. The first launch downloads the speech model.
# A running copy is asked to quit, as the menu does, so that it stops the recording and puts the clipboard back. Only a
# copy that is still there after about 5 seconds, or that cannot be asked, is killed.
run: build
	@if pgrep -x Susurro >/dev/null; then \
		if osascript -e 'tell application id "$(APP_ID)" to quit' >/dev/null 2>&1; then \
			for _ in $$(seq 50); do pgrep -x Susurro >/dev/null || break; sleep 0.1; done; \
		fi; \
		if pgrep -x Susurro >/dev/null; then echo "Susurro did not quit; stopping it."; pkill -x Susurro || true; fi; \
	fi
	open $(APP)

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT) Packages/*/.build
