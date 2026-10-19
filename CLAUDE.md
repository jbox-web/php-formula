# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The parent directory's `CLAUDE.md` (`../CLAUDE.md`) describes the toolchain,
CI, lint rules and the `template-formula` layout shared by the 32 forks. This
file only covers what differs here: **php-formula does not follow that
template**, so most of the generic architecture described there does not apply.

## Commands

One Kitchen suite, `debian`, on the three fleet platforms, so instance names are
`debian-<platform>`:

```bash
bin/kitchen list
bin/kitchen converge debian-debian-13-3008-2
bin/kitchen verify   debian-debian-13-3008-2
bin/kitchen test     debian-debian-11-3006-27
pre-commit run --all-files
```

The suite's `state_top` is the exact set of states applied in production:
`php.fpm.install`, `php.fpm.config`, `php.fpm.pools`,
`php.modules`, `php.fpm.service` (plus `states.repo` and `php._mapdata`).
Anything outside that list (apache2, hhvm, xcache, composer, repo, the
per-extension states called directly…) is not exercised by any test.

## Architecture

### `map.jinja` is one monolithic dict, not the YAML chain

There is no `defaults.yaml` / `os*map.yaml`. `php/map.jinja` (~3400 lines) is a
cascade of `if grains.os == "Ubuntu"` (split on `use_external_repo`, then on
`osrelease`) / `elif grains.os == "Debian"` / `else`, each branch
calling `salt['pillar.get']('php', {'lookup': grains.filter_by({...})},
merge=True)`. The Debian branch (`elif ... == "Debian"`) is the only one the
fleet reaches; it has no per-release distinction and assumes the sury.org
package names `php<ver>-<ext>` and paths `/etc/php/<ver>/...`. A change to a
Debian default goes there, not in the `else` branch, which also contains a
`Debian:` key.

The whole pillar `php:` tree is merged over the defaults, so pillar keys live
both under `php:lookup:` (package names, paths, `fpm:defaults`) and directly
under `php:` (`fpm:config`, `fpm:pools`, `cli:ini`, `modules`, `version`, `repo`).

### Multi-version: everything is derived from the *first* version

`php:version` is a string or a list. `map.jinja` builds every package name and
path with `php_version = version[0]`; every other version is then obtained by
**string replacement** of that first version (`pkg.replace(first, other)`,
`path|replace(first, version)`). Consequences:

- Each consumer has two code paths: `if pillar_php_version is iterable and not
  string` (state IDs suffixed `_<version>`, e.g. `php_fpm_service_7.3`) and the
  single-version path (unsuffixed IDs). A fix in one branch must be checked in
  the other — `fpm/config.sls` documents one such divergence that was fixed.
- A lookup value that does not contain the first version string (e.g.
  `php-imagick`, `php-xdebug`) is not multiplied per version.
- Each FPM pool picks its version with `phpversion` (default `'7.0'`), replaced
  into the first version's `pool.d` path in `fpm/pools_config.sls`.

### Package installation goes through `installed.jinja`

Most leaf states are two lines: `{% set state = '<key>' %}` then
`{% include "php/installed.jinja" %}`. That template reads
`php.lookup.pkgs[<key>]` (string or list; dict entries become extra
`pkg.installed` states via `sls_block`), expands it per version, deduplicates,
and emits `php_install_<key>`. For `php`, `cli` and `fpm` it can also manage the
ondrej PPA / sury.org repo when `use_external_repo` is true. Production leaves
it unset: the repository is declared by apt-formula (reproduced in
`test/salt/states/repo.sls`).

`php.modules` loops over `php:modules`: a module with its own `php/<name>.sls`
is included, any other one is rendered inline through `installed.jinja`. The
include re-renders `map.jinja` once per module.

### Ini rendering

`ini.jinja`'s `php_ini()` macro manages `php.ini`, `php-fpm.conf` and every pool
file with the same TOFS template, `php/files/default/php.ini`, fed with
`serialize(odict(settings))` (dicts turned into ordered lists of one-key
dicts). Top-level scalars become `key = value`, dicts become `[section]`
blocks. FPM and CLI ini settings start from `php.ini.defaults` and the pillar
overrides are merged per section.

### Leftovers

- `php/ng/*.sls` are shims that include `php.deprecated`, a `test.fail` with
  `failhard: True`. Never include `php.ng.*`.
- `test/integration/default/files/_mapdata/` keeps upstream dumps for ~28
  platforms; only `debian-11.yaml` and `debian-13.yaml` are compared. The test
  pillar sets two versions (`5.6`, `7.3`) and two pools, and the dump includes
  the merged pillar: any change to `test/salt/pillar/debian.sls` or to the
  Debian branch of `map.jinja` must be carried into both files.
- `cli/install.sls` (reached through `php:modules: [cli]`) renders an
  `alternatives.set` state with a single-version `php:version`, or with a list
  only when `php:alternatives_version` is set. The `alternatives` state module
  no longer exists in Salt 3008; the execution module it also calls at render
  time (`alternatives.show_current`) does.
