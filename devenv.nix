{ pkgs, lib, config, inputs, ... }:

{
  git-hooks.hooks = {
    actionlint.enable = true;
    check-toml.enable = true;
    check-vcs-permalinks.enable = true;
    markdownlint.enable = true;
    shellcheck = {
      enable = true;
      excludes = [
        ".*\.zsh$"
      ];
    };
    typos.enable = true;
    zizmor.enable = true;
  };
}
