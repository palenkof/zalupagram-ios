load("@rules_cc//cc:objc_library.bzl", "objc_library")

# The animated pixel sky, the same source files as in ZalupaGram Desktop.
objc_library(
    name = "ZalupaGramSkyCore",
    enable_modules = True,
    module_name = "ZalupaGramSkyCore",
    srcs = glob([
        "Sources/*.cpp",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
        "PublicHeaders/ZalupaGramSkyCore",
    ],
    copts = [
        "-std=c++20",
    ],
    visibility = [
        "//visibility:public",
    ],
)
