load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ZalupaGramSky",
    module_name = "ZalupaGramSky",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/ZalupaGramCore",
        "//submodules/ZalupaGramSkyCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
