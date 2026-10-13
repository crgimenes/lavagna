# lavagna: the backends as static libraries, the examples as app bundles,
# and the QA gate.
CC = xcrun clang
LLVM ?= /opt/homebrew/opt/llvm/bin
WARN = -Wall -Wextra -Werror -Wshadow -Wconversion -Wdouble-promotion -Wundef
MACOS_MIN = 14.0
CFLAGS ?= -std=c11 -O2 $(WARN) -mmacosx-version-min=$(MACOS_MIN)
OBJCFLAGS = -fobjc-arc -O2 $(WARN) -mmacosx-version-min=$(MACOS_MIN)
FRAMEWORKS = -framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers
EXAMPLES = scribble pixels
COMMON = lavagna.h lavagna_core.h lavagna_metal.h lavagna_image.h
MACOS_OBJ = build/macos/lavagna_core.o build/macos/lavagna_apple.o build/macos/lavagna_image.o \
	build/macos/lavagna_metal.o \
	build/macos/lavagna_macos.o
IOS_MIN = 17.0
SIM_SDK = $(shell xcrun --sdk iphonesimulator --show-sdk-path)
SIM = -target arm64-apple-ios$(IOS_MIN)-simulator -isysroot $(SIM_SDK)
IOS_FRAMEWORKS = -framework UIKit -framework Foundation -framework CoreGraphics -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers -lobjc
SIM_OBJ = build/ios-sim/lavagna_core.o build/ios-sim/lavagna_apple.o build/ios-sim/lavagna_image.o \
	build/ios-sim/lavagna_metal.o \
	build/ios-sim/lavagna_ios.o
TIDY_CHECKS = bugprone-*,cert-*,clang-analyzer-*,readability-*,-readability-magic-numbers,-readability-function-cognitive-complexity,-readability-identifier-length,-readability-braces-around-statements,-bugprone-easily-swappable-parameters,-readability-else-after-return,-readability-math-missing-parentheses,-readability-uppercase-literal-suffix,-cert-err33-c,-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling

.PHONY: all lib ios lib-ios-sim wasm fmt fmt-check tidy check freestanding qa size clean

all: lib $(EXAMPLES:%=build/%.app)

lib: build/macos/liblavagna.a

build/macos/%.o: %.c $(COMMON)
	@mkdir -p build/macos
	$(CC) $(CFLAGS) -c -o $@ $<

build/macos/%.o: %.m $(COMMON)
	@mkdir -p build/macos
	$(CC) $(OBJCFLAGS) -c -o $@ $<

build/macos/liblavagna.a: $(MACOS_OBJ)
	rm -f $@
	ar rcs $@ $^

WASM = --target=wasm32 -std=c11 -O2 -ffreestanding -nostdlib -fno-builtin $(WARN) \
	-Wl,--no-entry -Wl,--strip-all

# The examples for the browser: each .wasm beside lavagna.js and a page.
wasm: $(EXAMPLES:%=build/wasm/%.wasm) build/wasm/lavagna.js build/wasm/index.html

build/wasm/%.wasm: examples/%.c lavagna_core.c lavagna_wasm.c lavagna.h lavagna_core.h
	@mkdir -p build/wasm
	$(LLVM)/clang $(WASM) -o $@ $< lavagna_core.c lavagna_wasm.c

build/wasm/lavagna.js: lavagna.js
	@mkdir -p build/wasm
	cp $< $@

build/wasm/index.html: examples/index.html
	@mkdir -p build/wasm
	cp $< $@

lib-ios-sim: build/ios-sim/liblavagna.a

ios: $(EXAMPLES:%=build/ios-sim/%.app)

build/ios-sim/%.o: %.c $(COMMON)
	@mkdir -p build/ios-sim
	$(CC) -std=c11 -O2 $(WARN) $(SIM) -c -o $@ $<

build/ios-sim/%.o: %.m $(COMMON)
	@mkdir -p build/ios-sim
	$(CC) -fobjc-arc -O2 $(WARN) $(SIM) -c -o $@ $<

build/ios-sim/liblavagna.a: $(SIM_OBJ)
	rm -f $@
	ar rcs $@ $^

# An iOS app bundle: the executable at its root, scenes in the Info.plist,
# documents visible in Files, signed ad hoc for the simulator.
build/ios-sim/%.app: examples/%.c lavagna.h build/ios-sim/liblavagna.a
	@mkdir -p $@
	$(CC) -std=c11 -O2 $(WARN) -ffreestanding $(SIM) -Wl,-dead_strip $(IOS_FRAMEWORKS) \
		-o $@/$* $< build/ios-sim/liblavagna.a
	@printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>CFBundleExecutable</key><string>$*</string>' \
		'<key>CFBundleIdentifier</key><string>br.eti.crg.lavagna.$*</string>' \
		'<key>CFBundleName</key><string>$*</string>' \
		'<key>CFBundlePackageType</key><string>APPL</string>' \
		'<key>CFBundleVersion</key><string>1</string>' \
		'<key>CFBundleShortVersionString</key><string>0.1</string>' \
		'<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>' \
		'<key>MinimumOSVersion</key><string>$(IOS_MIN)</string>' \
		'<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>' \
		'<key>UILaunchScreen</key><dict/>' \
		'<key>UIFileSharingEnabled</key><true/>' \
		'<key>LSSupportsOpeningDocumentsInPlace</key><true/>' \
		'<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationPortraitUpsideDown</string></array>' \
		'<key>UIApplicationSceneManifest</key><dict>' \
		'<key>UIApplicationSupportsMultipleScenes</key><false/>' \
		'<key>UISceneConfigurations</key><dict><key>UIWindowSceneSessionRoleApplication</key><array><dict>' \
		'<key>UISceneConfigurationName</key><string>Default</string>' \
		'<key>UISceneDelegateClassName</key><string>LavSceneDelegate</string>' \
		'</dict></array></dict></dict>' \
		'</dict></plist>' > $@/Info.plist
	codesign --force --sign - $@ 2>/dev/null

build/%.o: examples/%.c lavagna.h
	@mkdir -p build
	$(CC) $(CFLAGS) -ffreestanding -c -o $@ $<

build/%.app: build/%.o build/macos/liblavagna.a
	@mkdir -p $@/Contents/MacOS
	$(CC) -mmacosx-version-min=$(MACOS_MIN) -Wl,-dead_strip -Wl,-x $(FRAMEWORKS) \
		-o $@/Contents/MacOS/$* $^
	@printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>CFBundleExecutable</key><string>$*</string>' \
		'<key>CFBundleIdentifier</key><string>br.eti.crg.lavagna.$*</string>' \
		'<key>CFBundleName</key><string>$*</string>' \
		'<key>CFBundlePackageType</key><string>APPL</string>' \
		'<key>LSMinimumSystemVersion</key><string>$(MACOS_MIN)</string>' \
		'<key>NSHighResolutionCapable</key><true/>' \
		'</dict></plist>' > $@/Contents/Info.plist

size: all
	@for e in $(EXAMPLES); do ls -l build/$$e.app/Contents/MacOS/$$e; done

fmt:
	$(LLVM)/clang-format -i *.h *.c *.m examples/*.c

fmt-check:
	$(LLVM)/clang-format --dry-run --Werror *.h *.c *.m examples/*.c

tidy:
	$(LLVM)/clang-tidy --quiet --warnings-as-errors='*' --checks='$(TIDY_CHECKS)' \
		examples/*.c lavagna_core.c lavagna_apple.c lavagna_image.c -- -std=c11 -isysroot $(shell xcrun --show-sdk-path)
	$(LLVM)/clang-tidy --quiet --warnings-as-errors='*' --checks='$(TIDY_CHECKS)' \
		lavagna_wasm.c -- -std=c11 --target=wasm32 -ffreestanding

check:
	cppcheck --enable=warning,style,performance,portability --inline-suppr \
		--suppress=missingIncludeSystem --error-exitcode=1 examples/*.c lavagna_core.c lavagna_apple.c \
		lavagna_image.c \
		lavagna_wasm.c

# Programs build for a target with no C library at all.
freestanding:
	@mkdir -p build
	@for e in $(EXAMPLES); do \
		$(LLVM)/clang --target=wasm32 -ffreestanding -nostdlib -fno-builtin -c \
			-std=c11 -O2 $(WARN) -o build/$${e}_wasm.o examples/$$e.c || exit 1; \
	done
	$(LLVM)/clang --target=wasm32 -ffreestanding -nostdlib -fno-builtin -c \
		-std=c11 -O2 $(WARN) -o build/lavagna_core_wasm.o lavagna_core.c

qa: all wasm fmt-check tidy check freestanding

clean:
	rm -rf build
