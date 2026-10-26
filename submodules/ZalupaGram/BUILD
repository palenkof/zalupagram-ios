load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

genrule(
    name = "ZalupaGramGeneratedSource",
    srcs = [
        "//zalupagram:version.json",
        "//zalupagram:update_token",
    ],
    tools = ["//zalupagram:ci/gen_sources.py"],
    outs = ["ZalupaGramGenerated.swift"],
    cmd = "python3 $(location //zalupagram:ci/gen_sources.py) --version $(location //zalupagram:version.json) --token-files \"$(locations //zalupagram:update_token)\" --out $@",
)

swift_library(
    name = "ZalupaGram",
    module_name = "ZalupaGram",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        ":ZalupaGramGeneratedSource",
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
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/ZalupaGramCore",
        "//submodules/TextFormat:TextFormat",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//third-party/ZipArchive:ZipArchive",
    ],
    visibility = [
        "//visibility:public",
    ],
)
