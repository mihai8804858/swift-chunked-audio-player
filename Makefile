NAME = ChunkedAudioPlayer
CONFIG = debug

GENERIC_PLATFORM_IOS = generic/platform=iOS
GENERIC_PLATFORM_MACOS = platform=macOS
GENERIC_PLATFORM_MAC_CATALYST = platform=macOS,variant=Mac Catalyst
GENERIC_PLATFORM_TVOS = generic/platform=tvOS
GENERIC_PLATFORM_VISIONOS = generic/platform=visionOS

GREEN='\033[0;32m'
NC='\033[0m'

build-all-platforms:
	for platform in \
	  "$(GENERIC_PLATFORM_IOS)" \
	  "$(GENERIC_PLATFORM_MACOS)" \
	  "$(GENERIC_PLATFORM_MAC_CATALYST)" \
	  "$(GENERIC_PLATFORM_TVOS)" \
	  "$(GENERIC_PLATFORM_VISIONOS)"; \
	do \
		echo -e "\n${GREEN}Building $$platform ${NC}"\n; \
		set -o pipefail && xcrun xcodebuild build \
			-workspace $(NAME).xcworkspace \
			-scheme $(NAME) \
			-configuration $(CONFIG) \
			-destination "$$platform" | xcpretty || exit 1; \
	done;

lint:
	swiftlint lint --strict

.PHONY: lint build-all-platforms

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef
