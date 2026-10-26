load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

genrule(
    name = "ZalupaGramVersionSource",
    srcs = ["//zalupagram:version.json"],
    outs = ["ZalupaGramVersion.swift"],
    cmd = """
        version=$$(python3 -c "import json; print(json.load(open('$(location //zalupagram:version.json)'))['version'])")
        echo "// Generated from zalupagram/version.json." > $@
        echo "let zalupaGramVersion = \\"$$version\\"" >> $@
    """,
)

swift_library(
    name = "ZalupaGram",
    module_name = "ZalupaGram",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        ":ZalupaGramVersionSource",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AccountContext:AccountContext",
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)
