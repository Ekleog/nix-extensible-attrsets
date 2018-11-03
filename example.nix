# Known issues of this prototype:
#  * Not using the NixOS module system's types for demonstration simplicity
#  * Not checking the values of the set initially passed to make-extensible
# Both points would be relatively easy to fix but would obscure the main point
# here: demonstrating a simple example of extensible attrsets
with import <nixpkgs> {};
let
  # values defined in the first `set` are not type-checked, this is a bug left
  # here so that the example stays easily readable
  make-extensible = set: set // {
    __functor = self: new:
      let metadata = self.metadata // new.metadata; in
      self // builtins.foldl' lib.recursiveUpdate {} (
        builtins.map (n:
          if n == "metadata"
          then { inherit metadata; }
          else
            if self ? n
            then {
              ${n} = args: metadata.${n}.merge (self.${n} args) (new.${n} args);
              metadata.${n}.extattrset-deps = builtins.attrNames (
                builtins.functionArgs self.${n} //
                builtins.functionArgs new.${n}
              );
            }
            else {
              ${n} = new.${n};
            }
        ) (builtins.attrNames new)
    );
  };

  extract = s: v: s.${v} (builtins.foldl' (a: x: a // x) {} (
    builtins.map (n: {
      ${n} = extract s n;
    }) (
      s.metadata.${v}.extattrset-deps or
        (builtins.attrNames (builtins.functionArgs s.${v}))
    )
  ));

  # Example from the gist

  derivation-builder = make-extensible {
    metadata.name = {
      doc = "Name of the derivation, used in the Nix store path.";
      check = builtins.isString;
      example = "openssl";
    };

    version = {...}: "";
    metadata.version = {
      doc = "Version of the derivation, used in the Nix store path.";
      check = builtins.isString;
      example = "1.0.2";
    };

    metadata.builder = {
      doc = "Command to be executed to build the derivation.";
      check = x: builtins.typeOf x == "path";
      example = "${pkgs.bash}/bin/sh";
    };

    args = {...}: [];
    metadata.args = {
      doc = "Arguments passed to the builder.";
      check = builtins.isList;
    };

    outputs = {...}: ["out"];
    metadata.outputs = {
      doc = "Symbolic names of the outputs of this derivation.";
      check = builtins.isList;
    };

    env = {outputs, ...}: { inherit outputs; };
    metadata.env = {
      doc = "Structured values passed to the builder.";
      check = builtins.isAttrs;
      merge = a: b: a // b;
    };

    # Note: I haven't checked whether this is correct as it wasn't mentioned in
    # the gist, but it appears to work here... should be checked before any kind
    # of deployment
    system = {}: builtins.currentSystem;
    metadata.system = {
      check = _: true;
    };

    drv = {name, version, builder, args, env, ...}: builtins.derivation ({
      name = "${name}-${version}";
      inherit builder args system;
    } // env);
  };

  generic-builder = derivation-builder {
    buildInputs = {...}: [];
    metadata.buildInputs = {
      doc = "Dependencies of this derivation.";
      check = builtins.isList;
      merge = a: b: a ++ b;
    };

    # ...

    # implementation

    builder = {...}: builtins.toPath "${pkgs.bash}/bin/bash";
    args = {...}: [ "-c" (pkgs.writeScript "test-builder"
    "${pkgs.coreutils}/bin/env; ${pkgs.coreutils}/bin/touch $out") ];
    env = {buildInputs, ...}: { inherit buildInputs; };
  };

  example-derivation = generic-builder {
    name = {}: "example";
    version = {}: "1.0";
  };
in
  extract example-derivation "drv"
