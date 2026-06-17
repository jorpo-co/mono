# mono Commands — Full Reference

## `mono init`

Initialize repo as a mono monorepo.

```
mono init [--roots <csv> | -r <csv>] [--default-root <root>]
```

- Requires fresh repo with zero commits
- Creates `.gitmono` with roots, default-root, and base branch
- Creates empty root commit tagged `v0.0.0`

**Default behavior** (no flags): single root `modules`, default-root `modules`.

## `mono module add`

Create new module.

```
mono module add [-r <root>] [--branch <branch>] <name>
mono module add <root>/<name>
```

Without `--branch`:
1. Create orphan branch `<root>/<name>/main` from `v0.0.0`
2. Tag `<root>/<name>/v0.0.0`
3. Push orphan branch to origin (silent if no origin)
4. Switch to base branch
5. `git submodule add ./ <path>` (self-referencing URL)
6. Configure bidirectional alternates
7. Commit submodule reference to parent

With `--branch`:
- Register existing branch as module instead of creating new orphan
- Tag existing HEAD as `<root>/<name>/v0.0.0`

## `mono module tag`

Tag a module's current HEAD.

```
mono module tag [-r <root>] [--pin|-p] <name> <semver>
mono module tag [--pin|-p] <root>/<name> <semver>
```

1. Read submodule HEAD SHA via `.git/modules/<path>`
2. `git update-ref refs/heads/<branch>` = SHA
3. Create annotated tag `<root>/<name>/v<semver>` pointing to SHA
4. With `--pin`: update parent gitlink + commit

## `mono module pin`

Pin parent's submodule reference.

```
mono module pin [-r <root>] <name> [<version>]
mono module pin <root>/<name> [<version>]
```

With version:
- Look up tag `<root>/<name>/v<version>` in parent namespace
- Resolve to commit SHA
- `git add <path>` + `git commit`

Without version:
- Read submodule HEAD directly
- Pin to that SHA

## `mono module version`

Show pinned version.

```
mono module version [-r <root>] <name>
mono module version <root>/<name>
```

- `git ls-tree HEAD <path>` to get gitlink SHA
- `git tag --points-at <sha>` to find matching tag
- Output: `<tag> (<sha>)` or `<sha> (no tag)`

## `mono module split`

Extract folder into submodule.

```
mono module split <root>/<name>
```

1. `git subtree split --prefix=<path> -b <branch>` extracts folder history
2. `git rm -rf <path>` removes from main
3. Commit removal
4. `_create_module <name> <root> <branch>` registers as module

## `mono clone`

Full checkout after `git clone`.

```
mono clone
```

1. `git submodule update --init --recursive`
2. `mono setup`

## `mono setup`

Prepare submodules for development.

```
mono setup
```

For each registered module:
1. Regenerate bidirectional alternates (idempotent)
2. Switch submodule from detached HEAD to tracked branch

## `mono push`

Push everything.

```
mono push
```

1. Push base branch (default: main)
2. Push every module's orphan branch
3. Push all tags

## `mono config`

Read/write config.

```
mono config <key> [<value>]
mono config --root-list
mono config --default-root
```

Writes to `.gitmono` via `git config -f`.

## Internal Helpers

| Helper | Purpose |
|---|---|
| `_resolve_module` | Normalize bare name / `-r root name` / `root/name` into `$root`, `$name`, `$path` |
| `_get_root_list` | Read roots from `.gitmono` (handles backward compat) |
| `_get_default_root` | Read default root (handles backward compat) |
| `_validate_root` | Check root is in configured list |
| `_get_module_branch_name` | Build `<root>/<name>/<base>` |
| `_get_module_path` | Build `<root>/<name>` |
| `_setup_alternates` | Write bidirectional alternates files |
| `_has_branch` | Check ref exists |
| `_create_module_branch` | Create orphan branch from `v0.0.0` |
| `_create_real_module` | Register as git submodule (`git submodule add ./ <path>`) |