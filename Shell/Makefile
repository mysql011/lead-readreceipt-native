TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := Turrit
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := GRRShell
GRRShell_FILES := GRRShell.m
GRRShell_FRAMEWORKS := UIKit Foundation
GRRShell_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
