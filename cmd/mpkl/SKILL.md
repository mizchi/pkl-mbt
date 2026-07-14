---
name: mpkl
description: Use mpkl to parse, typecheck, evaluate, or normalize Apple Pkl files and inline source in a WebAssembly command. Use when an agent needs to validate a local Pkl file tree with relative imports or cached package:// dependencies, inspect evaluated configuration as PCF, JSON, YAML, properties, plist, textproto, XML, or Jsonnet, or compare a small Pkl snippet without installing Apple Pkl.
---

# mpkl

Run `mpkl` through the MoonBit Skills Marketplace when a task needs a quick,
local check of Pkl source or a local Pkl file tree.

## Run

Pass a file path to load it from the current working directory. Relative
`import`, expression-level `import()`, `extends`, and `amends` dependencies are
loaded recursively:

```bash
moon runwasm mizchi/pkl/cmd/mpkl -- check config.pkl
moon runwasm mizchi/pkl/cmd/mpkl -- eval --format json config.pkl
```

`package://` dependencies are resolved from a pre-extracted mpkl package
cache. Pass a cache explicitly when it is not in the default location:

```bash
moon runwasm mizchi/pkl/cmd/mpkl -- eval --format json \
  --package-cache .pkl-packages Taskfile.pkl
```

`--package-cache` is repeatable. Without it, mpkl checks
`$PKL_MBT_PACKAGE_CACHE`, `$XDG_CACHE_HOME/pkl-mbt/package-2`, then
`$HOME/.cache/pkl-mbt/package-2`. Populate the cache first with the native
`mpkl` CLI; the Wasm command does not download a cache miss.

For a small self-contained module, pass the complete text with `--source`:

```bash
moon runwasm mizchi/pkl/cmd/mpkl -- eval --format json --source 'answer = 6 * 7'
```

Use one of these commands:

- `parse`: validate syntax and print `ok`.
- `check`: parse and typecheck the module, then print its inferred type.
- `eval`: evaluate the module and render its value. Select `pcf`, `json`,
  `yaml`, `properties`, `plist`, `textproto`, `xml`, or `jsonnet` with
  `--format`; the default is `pcf`.
- `format`: evaluate the module and emit canonical PCF. Treat this as value
  normalization, not as a comment-preserving source formatter.

When using `--source`, preserve newlines and quote the argument so the shell
does not interpret Pkl interpolation or punctuation.

## Constraints

File paths are host paths resolved from the process working directory. Without
a Moonrun policy, the command inherits Moonrun's legacy filesystem access. For
an agent or untrusted project, pass a deny-by-default policy that exposes only
the required tree:

```toml
[fs]
read = ["config"]
```

```bash
moon runwasm --experimental-policy moonrun-policy.toml \
  mizchi/pkl/cmd/mpkl -- eval config/main.pkl
```

File mode resolves `package://` and `projectpackage://` URIs only from an
already extracted package cache. It does not fetch HTTP or a missing package,
and does not currently expand import globs or provide Pkl resource reads and
environment properties. Use the native `mpkl` CLI to populate a package cache
or when the task needs those capabilities.

Interpret exit codes as follows:

- `0`: the requested operation succeeded.
- `1`: Pkl parsing, typechecking, or evaluation produced diagnostics.
- `2`: the command line is invalid or requests an unsupported operation.
