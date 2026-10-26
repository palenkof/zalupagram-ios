exports_files([
    "version.json",
    "ci/gen_sources.py",
])

# Only on the build machine, written from the UPDATE_TOKEN secret.
filegroup(
    name = "update_token",
    srcs = glob(["update_token.txt"], allow_empty = True),
    visibility = ["//visibility:public"],
)
