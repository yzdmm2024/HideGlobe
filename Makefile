# ============ HideGlobe Makefile：rootless tweak + 设置面板 ============
# TARGET 14.5（theos/sdks）——新 Xcode SDK 无私有框架 tbd，链不了 Preferences
TARGET := iphone:clang:14.5:14.0
# arm64e 设备的「设置」进程跑 arm64e，纯 arm64 的 bundle 加载报「已损坏或丢失必要的资源」
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# ===== Tweak 本体 =====
TWEAK_NAME = HideGlobe
HideGlobe_FILES = src/Tweak.xm
HideGlobe_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w
HideGlobe_FRAMEWORKS = UIKit Foundation CoreGraphics

# ===== 设置面板 PreferenceBundle =====
# Info.plist / Root.plist 放 layout/Library/PreferenceBundles/HideGlobePrefs.bundle/
BUNDLE_NAME = HideGlobePrefs
HideGlobePrefs_FILES = Preferences/HGSettingsController.m
HideGlobePrefs_INSTALL_PATH = /Library/PreferenceBundles
HideGlobePrefs_FRAMEWORKS = UIKit Foundation
# 必须显式链接 Preferences（chained fixups 下 dynamic_lookup 会被 dyld 拒载）
HideGlobePrefs_PRIVATE_FRAMEWORKS = Preferences
# theos 只发 -framework 不发搜索路径，必须手动补 -F
HideGlobePrefs_LDFLAGS = -F$(TARGET_PRIVATE_FRAMEWORK_PATH)
HideGlobePrefs_CFLAGS = -fobjc-arc -fobjc-exceptions -w

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
