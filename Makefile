export BUILDTYPE ?= Release
export ENABLE_COVERAGE ?= 0

ifeq ($(shell uname -s), Darwin)
  HOST_PLATFORM = osx
  export JOBS ?= $(shell sysctl -n hw.ncpu)
else ifeq ($(shell uname -s), Linux)
  HOST_PLATFORM = linux
  export JOBS ?= $(shell grep --count processor /proc/cpuinfo)
else
  $(error Cannot determine host platform)
endif

ifeq ($(V), 1)
  export XCPRETTY
else
  export XCPRETTY ?= | xcpretty
endif

ifneq (,$(wildcard .git/.))
.mason:
	git submodule update --init
else
.mason: ;
endif

default:
	@printf "You must specify a valid target\n"

# Depend on gyp includes plus directories, so that projects are regenerated when
# files are added or removed.
GYP_DEPENDENCIES = mbgl.gypi test/test.gypi bin/*.gypi $(shell find src include -type d)

#### OS X targets ##############################################################

OSX_OUTPUT_PATH = build/osx
OSX_PROJ_PATH = $(OSX_OUTPUT_PATH)/platform/osx/platform.xcodeproj
OSX_WORK_PATH = platform/osx/osx.xcworkspace
OSX_USER_DATA_PATH = $(OSX_WORK_PATH)/xcuserdata/$(USER).xcuserdatad

$(OSX_OUTPUT_PATH)/config.gypi: platform/osx/scripts/configure.sh .mason configure
	./configure $< $@ osx

$(OSX_OUTPUT_PATH)/mbgl.xcconfig: $(OSX_OUTPUT_PATH)/config.gypi
	./scripts/export-xcconfig.py $< $@

$(OSX_PROJ_PATH): platform/osx/platform.gyp $(OSX_OUTPUT_PATH)/config.gypi $(OSX_OUTPUT_PATH)/mbgl.xcconfig $(GYP_DEPENDENCIES)
	./deps/run_gyp -f xcode --depth=. --generator-output=$(OSX_OUTPUT_PATH) $<

osx: $(OSX_PROJ_PATH)
	set -o pipefail && xcodebuild \
	  -derivedDataPath $(OSX_OUTPUT_PATH) \
	  -configuration $(BUILDTYPE) \
	  -workspace $(OSX_WORK_PATH) -scheme CI build $(XCPRETTY)

xproj: $(OSX_PROJ_PATH) $(OSX_WORK_PATH)
	mkdir -p "$(OSX_USER_DATA_PATH)"
	cp platform/osx/WorkspaceSettings.xcsettings "$(OSX_USER_DATA_PATH)/WorkspaceSettings.xcsettings"
	open $(OSX_WORK_PATH)

test-osx: osx node_modules/express
	ulimit -c unlimited && ($(OSX_OUTPUT_PATH)/Build/Products/$(BUILDTYPE)/test & pid=$$! && wait $$pid \
	  || (lldb -c /cores/core.$$pid --batch --one-line 'thread backtrace all' --one-line 'quit' && exit 1))
	set -o pipefail && xcodebuild \
	  -derivedDataPath $(OSX_OUTPUT_PATH) \
	  -configuration $(BUILDTYPE) \
	  -workspace $(OSX_WORK_PATH) -scheme CI test $(XCPRETTY)

xpackage: $(OSX_PROJ_PATH)
	SYMBOLS=$(SYMBOLS) ./platform/osx/scripts/package.sh

xdocument:
	OUTPUT=$(OUTPUT) ./platform/osx/scripts/document.sh

genstrings:
	genstrings -u -o platform/osx/sdk/Base.lproj platform/darwin/src/*.{m,mm}
	genstrings -u -o platform/osx/sdk/Base.lproj platform/osx/src/*.{m,mm}
	genstrings -u -o platform/ios/resources/Base.lproj platform/ios/src/*.{m,mm}
	-find platform/ios/resources platform/osx/sdk -path '*/Base.lproj/*.strings' -exec \
		textutil -convert txt -extension strings -inputencoding UTF-16 -encoding UTF-8 {} \;
	mv platform/osx/sdk/Base.lproj/Foundation.strings platform/darwin/resources/Base.lproj/

#### iOS targets ##############################################################

IOS_OUTPUT_PATH = build/ios
IOS_PROJ_PATH = $(IOS_OUTPUT_PATH)/platform/ios/platform.xcodeproj
IOS_WORK_PATH = platform/ios/ios.xcworkspace
IOS_USER_DATA_PATH = $(IOS_WORK_PATH)/xcuserdata/$(USER).xcuserdatad

$(IOS_OUTPUT_PATH)/config.gypi: platform/ios/scripts/configure.sh .mason configure
	./configure $< $@ ios

$(IOS_OUTPUT_PATH)/mbgl.xcconfig: $(IOS_OUTPUT_PATH)/config.gypi
	./scripts/export-xcconfig.py $< $@

$(IOS_PROJ_PATH): platform/ios/platform.gyp $(IOS_OUTPUT_PATH)/config.gypi $(IOS_OUTPUT_PATH)/mbgl.xcconfig $(GYP_DEPENDENCIES)
	./deps/run_gyp -f xcode --depth=. --generator-output=$(IOS_OUTPUT_PATH) $<

ios: $(IOS_PROJ_PATH)
	set -o pipefail && xcodebuild \
	  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES \
	  -derivedDataPath $(IOS_OUTPUT_PATH) \
	  -configuration $(BUILDTYPE) -sdk iphonesimulator \
	  -destination 'platform=iOS Simulator,name=iPhone 6,OS=latest' \
	  -workspace $(IOS_WORK_PATH) -scheme CI build $(XCPRETTY)

iproj: $(IOS_PROJ_PATH)
	mkdir -p "$(IOS_USER_DATA_PATH)"
	cp platform/ios/WorkspaceSettings.xcsettings "$(IOS_USER_DATA_PATH)/WorkspaceSettings.xcsettings"
	open $(IOS_WORK_PATH)

test-ios: ios
	ios-sim start --devicetypeid 'com.apple.CoreSimulator.SimDeviceType.iPhone-6,9.3'
	ios-sim launch $(IOS_OUTPUT_PATH)/Build/Products/$(BUILDTYPE)-iphonesimulator/ios-test.app --verbose --devicetypeid 'com.apple.CoreSimulator.SimDeviceType.iPhone-6,9.3'
	set -o pipefail && xcodebuild \
	  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES \
	  -derivedDataPath $(IOS_OUTPUT_PATH) \
	  -configuration $(BUILDTYPE) -sdk iphonesimulator \
	  -destination 'platform=iOS Simulator,name=iPhone 6,OS=latest' \
	  -workspace $(IOS_WORK_PATH) -scheme CI test $(XCPRETTY)

ipackage: $(IOS_PROJ_PATH)
	BITCODE=$(BITCODE) FORMAT=$(FORMAT) BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=$(SYMBOLS) \
	./platform/ios/scripts/package.sh

ipackage-strip: $(IOS_PROJ_PATH)
	BITCODE=$(BITCODE) FORMAT=$(FORMAT) BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=NO \
	./platform/ios/scripts/package.sh

ipackage-sim: $(IOS_PROJ_PATH)
	BUILDTYPE=Debug BITCODE=$(BITCODE) FORMAT=dynamic BUILD_DEVICE=false SYMBOLS=$(SYMBOLS) \
	./platform/ios/scripts/package.sh

iframework: $(IOS_PROJ_PATH)
	BITCODE=$(BITCODE) FORMAT=dynamic BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=$(SYMBOLS) \
	./platform/ios/scripts/package.sh

ifabric: $(IOS_PROJ_PATH)
	BITCODE=$(BITCODE) FORMAT=static BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=NO SELF_CONTAINED=YES \
	./platform/ios/scripts/package.sh

idocument:
	OUTPUT=$(OUTPUT) ./platform/ios/scripts/document.sh

#### Android targets #####################################################

ANDROID_ENV = platform/android/scripts/toolchain.sh
ANDROID_ABIS = arm-v5 arm-v7 arm-v8 x86 x86-64 mips

define ANDROID_RULES
build/android-$1/config.gypi: platform/android/scripts/configure.sh .mason configure
	$$(shell $(ANDROID_ENV) $1) ./configure $$< $$@ android $1

build/android-$1/Makefile: build/android-$1/config.gypi
	$$(shell $(ANDROID_ENV) $1) deps/run_gyp platform/android/platform.gyp -I$$< \
	  -Dcoverage= -Goutput_dir=. --depth=. --generator-output=build/android-$1 -f make-android

android-lib-$1: build/android-$1/Makefile
	$$(shell $(ANDROID_ENV) $1) $(MAKE) -j$(JOBS) -C build/android-$1 all

apackage: android-lib-$1
endef

$(foreach abi,$(ANDROID_ABIS),$(eval $(call ANDROID_RULES,$(abi))))

android: android-lib-arm-v7
	cd platform/android && ./gradlew --parallel --max-workers=$(JOBS) assemble$(BUILDTYPE)

test-android:
	cd platform/android && ./gradlew testReleaseUnitTest --continue

apackage:
	cd platform/android && ./gradlew --parallel-threads=$(JOBS) assemble$(BUILDTYPE)

#### Node targets #####################################################

NODE_PRE_GYP = $(shell npm bin)/node-pre-gyp
NODE_OUTPUT_PATH = build/node-$(HOST_PLATFORM)-$(shell uname -m)

node_modules: package.json
	npm update # Install dependencies but don't run our own install script.

$(NODE_OUTPUT_PATH)/config.gypi: platform/$(HOST_PLATFORM)/scripts/configure.sh .mason configure
	./configure $< $@ $(HOST_PLATFORM) $(shell uname -m)

node: $(NODE_OUTPUT_PATH)/config.gypi node_modules
	$(NODE_PRE_GYP) configure --clang -- -I$< \
	  -Dcoverage= -Dlibuv_cflags= -Dlibuv_ldflags= -Dlibuv_static_libs=
	$(NODE_PRE_GYP) build --clang

xnode: $(NODE_OUTPUT_PATH)/config.gypi
	$(NODE_PRE_GYP) configure --clang -- -I$< \
	  -Dcoverage= -Dlibuv_cflags= -Dlibuv_ldflags= -Dlibuv_static_libs= \
	  -f xcode
	./platform/node/scripts/create_node_scheme.sh "node test" "`npm bin tape`/tape platform/node/test/js/**/*.test.js"
	./platform/node/scripts/create_node_scheme.sh "npm run test-suite" "platform/node/test/render.test.js"
	open ./build/binding.xcodeproj

.PHONY: test-node
test-node: node
	npm test
	npm run test-suite

#### Qt targets #####################################################

QT_OUTPUT_PATH = build/qt-$(HOST_PLATFORM)-$(shell uname -m)
QT_MAKEFILE = $(QT_OUTPUT_PATH)/Makefile

# Cross compilation support
QT_ENV = $(shell MASON_PLATFORM_VERSION=$(shell uname -m) ./platform/qt/scripts/toolchain.sh)

$(QT_OUTPUT_PATH)/config.gypi: platform/qt/scripts/configure.sh .mason configure
	$(QT_ENV) ./configure $< $@ linux $(shell uname -m)

$(QT_MAKEFILE): $(QT_OUTPUT_PATH)/config.gypi
	$(QT_ENV) deps/run_gyp platform/qt/platform.gyp -I$< -Dcoverage=$(ENABLE_COVERAGE) \
	  -Goutput_dir=. --depth=. --generator-output=$(QT_OUTPUT_PATH) -f make

qt-lib: $(QT_MAKEFILE)
	$(QT_ENV) $(MAKE) -j$(JOBS) -C $(QT_OUTPUT_PATH) qt-lib

qt-app: $(QT_MAKEFILE)
	$(QT_ENV) $(MAKE) -j$(JOBS) -C $(QT_OUTPUT_PATH) qt-app

qt-qml-app: $(QT_MAKEFILE)
	$(QT_ENV) $(MAKE) -j$(JOBS) -C $(QT_OUTPUT_PATH) qt-qml-app

test-qt: $(QT_MAKEFILE) node_modules/express
	$(QT_ENV) $(MAKE) -j$(JOBS) -C $(QT_OUTPUT_PATH) test
	$(GDB) $(QT_OUTPUT_PATH)/$(BUILDTYPE)/test --gtest_catch_exceptions=0 --gtest_filter=*

run-qt-app: qt-app
	cd $(QT_OUTPUT_PATH)/$(BUILDTYPE) && ./qmapboxgl

run-qt-qml-app: qt-qml-app
	cd $(QT_OUTPUT_PATH)/$(BUILDTYPE) && ./qquickmapboxgl

#### Linux targets #####################################################

LINUX_OUTPUT_PATH = build/linux-$(shell uname -m)
LINUX_MAKEFILE = $(LINUX_OUTPUT_PATH)/Makefile

$(LINUX_OUTPUT_PATH)/config.gypi: platform/linux/scripts/configure.sh .mason configure
	./configure $< $@ linux $(shell uname -m)

$(LINUX_MAKEFILE): $(LINUX_OUTPUT_PATH)/config.gypi
	deps/run_gyp platform/linux/platform.gyp -I$< -Dcoverage=$(ENABLE_COVERAGE) \
	  -Goutput_dir=. --depth=. --generator-output=$(LINUX_OUTPUT_PATH) -f make

linux: glfw-app render offline

test-linux: test-*

render: $(LINUX_MAKEFILE)
	$(MAKE) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-render

offline: $(LINUX_MAKEFILE)
	$(MAKE) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-offline

glfw-app: $(LINUX_MAKEFILE)
	$(MAKE) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) glfw-app

test: $(LINUX_MAKEFILE)
	$(MAKE) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) test

run-glfw-app: glfw-app
	cd $(LINUX_OUTPUT_PATH)/$(BUILDTYPE) && ./mapbox-glfw

run-valgrind-glfw-app: glfw-app
	cd $(LINUX_OUTPUT_PATH)/$(BUILDTYPE) && valgrind --leak-check=full --suppressions=../../../scripts/valgrind.sup ./mapbox-glfw

ifneq (,$(shell which gdb))
  GDB = gdb -batch -return-child-result -ex 'set print thread-events off' -ex 'run' -ex 'thread apply all bt' --args
endif

test-%: node_modules/express test
	$(GDB) $(LINUX_OUTPUT_PATH)/$(BUILDTYPE)/test --gtest_catch_exceptions=0 --gtest_filter=$*

node_modules/express:
	npm install express@4.11.1

check: test
	scripts/collect-coverage.sh $(LINUX_OUTPUT_PATH)/$(BUILDTYPE)

# Generates a compilation database with ninja for use in clang tooling
compdb: $(LINUX_OUTPUT_PATH)/config.gypi
	deps/run_gyp platform/linux/platform.gyp $(GYP_FLAGS) -f ninja
	deps/ninja/ninja-linux -C $(LINUX_OUTPUT_PATH)/$(BUILDTYPE) \
		-t compdb cc cc_s cxx objc objcxx > $(LINUX_OUTPUT_PATH)/$(BUILDTYPE)/compile_commands.json

tidy: compdb
	deps/ninja/ninja-linux -C $(LINUX_OUTPUT_PATH)/$(BUILDTYPE) version shaders
	scripts/clang-tidy.sh $(LINUX_OUTPUT_PATH)/$(BUILDTYPE)

#### Miscellaneous targets #####################################################

clean:
	-find ./deps/gyp -name "*.pyc" -exec rm {} \;
	-rm -rf ./build \
	        ./platform/android/MapboxGLAndroidSDK/build \
	        ./platform/android/MapboxGLAndroidSDKTestApp/build \
	        ./platform/android/MapboxGLAndroidSDK/src/main/jniLibs \
	        ./platform/android/MapboxGLAndroidSDKTestApp/src/main/jniLibs \
	        ./platform/android/MapboxGLAndroidSDK/src/main/assets

distclean: clean
	-rm -rf ./mason_packages
	-rm -rf ./node_modules
