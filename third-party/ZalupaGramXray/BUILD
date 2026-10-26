load(
    "@build_bazel_rules_apple//apple:apple.bzl",
    "apple_static_xcframework_import",
)
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# ZalupaGram fork: Xray-core as a static library, built by CI with
# zalupagram/xray/build_ios.sh before the app.
apple_static_xcframework_import(
    name = "ZGXray",
    xcframework_imports = glob(["ZGXray.xcframework/**"]),
    visibility = [
        "//visibility:private",
    ],
)

objc_library(
    name = "ZalupaGramXray",
    enable_modules = True,
    module_name = "ZalupaGramXray",
    srcs = glob([
        "Sources/*.m",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    sdk_frameworks = [
        "Foundation",
        "Security",
        "CoreFoundation",
    ],
    sdk_dylibs = [
        "libresolv",
    ],
    deps = [
        ":ZGXray",
    ],
    visibility = [
        "//visibility:public",
    ],
)
