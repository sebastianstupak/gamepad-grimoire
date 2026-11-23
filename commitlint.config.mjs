// Conventional Commits: https://www.conventionalcommits.org
// Scopes follow the vertical slices (src/Features/*) plus repo-level areas.
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [
      2,
      "always",
      ["core", "controllers", "bindings", "profiles", "share", "commands", "cheatsheet", "diagnostics", "editor",
        "setup", "options", "art", "deps", "ci", "repo", "release"],
    ],
    "body-max-line-length": [1, "always", 100],
  },
};
