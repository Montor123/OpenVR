# Keep the pinned Cuttlefish board, kernel, HALs and partition layout.
$(call inherit-product, device/google/cuttlefish/vsoc_x86_64/phone/aosp_cf.mk)

PRODUCT_NAME := openvr_cf_x86_64_phone
PRODUCT_BRAND := OpenVR
PRODUCT_MANUFACTURER := OpenVR
PRODUCT_MODEL := OpenVR Lab x86_64

PRODUCT_PACKAGES += OpenVRLauncher

PRODUCT_COPY_FILES += \
    device/openvr/lab/openvr-home.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/preferred-apps/openvr-home.xml
