# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0

{ pkgs, ... }:
{
  packages = [
    pkgs.cvc5
    pkgs.just
    pkgs.rustup
    pkgs.elan
    pkgs.jq
    pkgs.coreutils
  ];
  env.CVC5 = "${pkgs.cvc5}/bin/cvc5";
}
