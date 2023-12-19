def _module_features_impl(module_ctx):
    feature_value = {}
    feature_configurable = {}

    for module in module_ctx.modules:
        for declare_tag in module.tags.declare:
            _validate_feature(declare_tag.feature, declare_tag)
            feature_value.setdefault(module.name, {})[declare_tag.feature] = False
            feature_configurable.setdefault(module.name, {})[declare_tag.feature] = declare_tag.configurable

    for module in module_ctx.modules:
        for require_tag in module.tags.require:
            if require_tag.module not in feature_value or require_tag.feature not in feature_value[require_tag.module]:
                fail("module '{}' requires undeclared feature '{}' from module '{}' in".format(
                    module.name,
                    require_tag.feature,
                    require_tag.module,
                ), require_tag)

            feature_value[module.name][require_tag.feature] = True

    _features_repo(
        name = "features",
        all_features = {module: features.keys() for module, features in feature_value.items()},
        enabled_features = {module: [
            feature
            for feature in features.keys()
            if features[feature]
        ] for module, features in feature_value.items()},
    )

def _validate_feature(feature, tag):
    # Ensure that features are valid Starlark identifiers.
    if not feature:
        fail("feature must not be empty in", tag)
    if feature.startswith("_") or feature.endswith("_"):
        fail("feature '{}' must not start or end with '_' in".format(feature), tag)
    if feature[0].isdigit():
        fail("feature '{}' must not start with a digit in".format(feature), tag)
    if not feature.replace("_", "").isalnum():
        fail("feature '{}' must consist of only alphanumeric characters and underscores".format(feature), tag)

_declare = tag_class(
    attrs = {
        "feature": attr.string(mandatory = True),
        "configurable": attr.bool(default = True),
    },
)

_require = tag_class(
    attrs = {
        "module": attr.string(mandatory = True),
        "feature": attr.string(mandatory = True),
    },
)

def _features_repo_impl(repository_ctx):
    feature_values = {}

    for module in repository_ctx.attr.all_features:
        for feature in repository_ctx.attr.all_features[module]:
            feature_values.setdefault(module, {})[feature] = False

    for module in repository_ctx.attr.enabled_features:
        for feature in repository_ctx.attr.enabled_features[module]:
            feature_values[module][feature] = True

    for module, features in feature_values.items():
        if module == "":
            module = "_main"

        header = """load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")

package(default_visibility = ["//visibility:public"])
"""
        build_file = "".join([header] + [
            _render_feature(feature, default)
            for feature, default in features.items()
        ])
        repository_ctx.file(
            "{}/BUILD.bazel".format(module),
            build_file,
            executable = False,
        )
    repository_ctx.file("WORKSPACE.bazel")

def _render_feature(feature, default):
    return """
bool_flag(
    name = "enable_{feature}",
    build_setting_default = {default},
)

config_setting(
    name = "{feature}",
    flag_values = {{
        ":enable_{feature}": "True",
    }},
)
""".format(feature = feature, default = default)

_features_repo = repository_rule(
    implementation = _features_repo_impl,
    attrs = {
        "all_features": attr.string_list_dict(mandatory = True),
        "enabled_features": attr.string_list_dict(mandatory = True),
    },
)

module_features = module_extension(
    implementation = _module_features_impl,
    tag_classes = {
        "declare": _declare,
        "require": _require,
    },
)
