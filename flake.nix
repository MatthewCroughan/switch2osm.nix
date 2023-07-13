{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/e603dc5";
    nixos-shell.url = "github:mic92/nixos-shell";
  };
  outputs = { self, nixpkgs, nixos-shell }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in
  {
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-shell.nixosModules.nixos-shell
        ./vm.nix
      ];
    };
    apps.x86_64-linux.vm = {
      type = "app";
      program = builtins.toPath (pkgs.writeShellScript "vm" ''
        export NIX_CONFIG="experimental-features = nix-command flakes"
        export PATH=$PATH:${pkgs.nixUnstable}/bin
        ${pkgs.nixos-shell}/bin/nixos-shell --flake ${self}#vm
      '');
    };
  };
}
