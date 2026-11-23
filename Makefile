TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := Turrit
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := GroupReadReceipt

GroupReadReceipt_FILES := \
	GroupReadReceipt.m \
	GRRSettings.m \
	GRRStorage.m \
	GRRNetwork.m \
	GRRMessageContext.m \
	GRRHookRegistry.m \
	GRRVisibilityTracker.m \
	GRRUI.m \
	GRRConfigViewController.m \
	GRRFishhookBridge.m \
	Headers/GRRMessageInfo.m

GroupReadReceipt_FRAMEWORKS := UIKit Foundation SystemConfiguration
GroupReadReceipt_LIBRARIES := substrate
GroupReadReceipt_CFLAGS := -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness
GroupReadReceipt_LDFLAGS := -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

before-package::
	@mkdir -p layout/Library/Application\ Support/GroupReadReceipt
	@cp GRRHooks.plist layout/Library/Application\ Support/GroupReadReceipt/GRRHooks.plist
