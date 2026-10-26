load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# ZalupaGram fork options read by TelegramCore, so no dependencies here.
swift_library(
    name = "ZalupaGramCore",
    module_name = "ZalupaGramCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)
