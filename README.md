# mono — Git Submodule Monorepo Manager

Lightweight bash script turning a plain Git repo into a monorepo using **submodules + orphan branches**. Zero deps beyond git.

Git submodules work but admin is tedious. `mono` automates branch creation, submodule wiring, tagging, and version tracking.

## Architecture

Each module lives as an **orphan branch** sharing a root commit tag. The base branch (`main`) holds submodule pointers via `.gitmodules`. All refs (branches, tags) live in **one repo** — no separate remotes needed.

```
repo root
  └── tag: root  (empty commit, shared ancestor)
        ├── main                              ← base branch (submodule pointers)
        ├── modules/auth/main                 ← orphan branch, auth module's history
        ├── modules/api/main                  ← orphan branch, api module's history
        └── libs/strutils/main                ← orphan branch, lib's history

.git/
├── refs/heads/main                               ← base branch ref
├── refs/heads/modules/auth/main                  ← auth orphan branch ref
├── refs/tags/root                                ← shared ancestor tag
├── refs/tags/modules/auth/root                   ← auth root tag
├── refs/tags/modules/auth/v1.2.0                 ← auth version tag (annotated)
└── modules/modules/auth/                         ← auth submodule git dir
    ├── objects/                                  ← auth's own object store
    └── objects/info/alternates                   ← points to parent objects
```

### Object store sharing

Parent and submodules share object stores via **bidirectional alternates** (auto-configured on `module add`):

```
.git/objects/info/alternates:
  ../modules/modules/auth/objects     ← parent sees auth's objects

.git/modules/modules/auth/objects/info/alternates:
  ../../../../objects                  ← auth sees parent's objects
```

This allows the parent to create annotated tags pointing to submodule commits, and to resolve `git tag --points-at <sha>` across module boundaries.

### Ref layout

| Kind | Pattern | Example |
|---|---|---|
| Module orphan branch | `<root>/<name>/<base>` | `modules/auth/main` |
| Module root tag | `<root>/<name>/root` | `modules/auth/root` |
| Module version tag | `<root>/<name>/v<semver>` | `modules/auth/v1.2.0` |
| Parent root tag | `root` | `root` |

## Setup

Requires **fresh repo with no commits**.

```bash
./mono init                                                # single root: modules
./mono init --roots modules,libs,plugins                    # multiple roots
./mono init -r libs,plugins                                 # shorthand
./mono init --roots modules,libs --default-root libs        # custom default root
```

Creates `.gitmono`:
```ini
[mono]
  roots = modules,libs,plugins
  default-root = modules
  base = main
```

Multiple roots (e.g. `modules`, `libs`, `plugins`) group modules by type. Each root gets its own branch prefix and submodule directory — same module name in different roots never collides.

## Commands

| Command | Description |
|---|---|
| `init [--roots <csv> \| -r <csv>] [--default-root <root>]` | Init repo, empty commit + root tag |
| `config <key> [value]` | Read/write `.gitmono` config |
| `config --root-list` | List configured roots (space-separated) |
| `config --default-root` | Show default root name |
| `module` | List registered submodules (reads `.gitmodules`) |
| `module add [-r <root>] <name>` | Create orphan branch + submodule + alternates |
| `module add <root>/<name>` | (alt) Full path syntax |
| `module tag [-r <root>] <name> <semver>` | Tag module version, update parent ref, pin in main |
| `module version [-r <root>] <name>` | Show pinned version of module in current HEAD |
| `module remove` | Not implemented yet |

## Usage

### Adding modules

```bash
# Bare name (uses default root → modules/auth)
mono module add auth

# Explicit root
mono module add -r libs strutils

# Full path
mono module add libs/strutils

# Ambiguous (-r AND path)
mono module add -r modules modules/auth  # Error: ambiguous
```

Each module creates:
- Orphan branch: `<root>/<name>/main`
- Root tag: `<root>/<name>/root`
- Submodule at `<root>/<name>/`
- Bidirectional alternates for object sharing

### Tagging a module version

Work inside the module, commit, then tag:

```bash
cd modules/auth
# ... edit files ...
git add -A
git commit -m "feat: add JWT token validation"
cd ../..
```

Three ways to specify the module:

```bash
# 1. Bare name (resolves via default root)
mono module tag auth v1.2.0

# 2. Explicit root flag
mono module tag -r modules auth v1.2.0
mono module tag -r libs strutils v0.5.1

# 3. Full path (split at /)
mono module tag modules/auth v1.2.0
mono module tag libs/strutils v0.5.1

# Error: -r and full path given together
mono module tag -r libs libs/strutils v1.0.0
# → "Error: ambiguous"
```

`mono module tag` does four things:

1. Reads the submodule's current HEAD commit SHA (via `--git-dir`)
2. Updates the parent's branch ref (`refs/heads/<root>/<name>/main`) to track the commit
3. Creates an **annotated** parent-level tag (`<root>/<name>/v<semver>`)
4. Pins the submodule reference in `main` and commits

The version (`v1.2.0` or `1.2.0`) is normalized — a leading `v` is stripped then re-added. Both `mono module tag auth 1.2.0` and `mono module tag auth v1.2.0` produce tag `modules/auth/v1.2.0`.

### Checking pinned versions

```bash
# Read the SHA pinned in main's tree, resolve to tag
mono module version modules/auth
# → modules/auth/v1.2.0 (abc123...)

mono module version auth
# → modules/auth/v1.2.0 (abc123...)

# If the pinned SHA has no tag:
mono module version auth
# → abc123... (no tag)
```

### Config

```bash
mono config mono.roots modules,libs
mono config mono.default-root libs
mono config mono.base develop          # change base branch
mono config mono.base                  # read current base
mono config --root-list                # modules libs
mono config --default-root             # libs
```

### Listing modules

```bash
mono module
# → submodule.modules/auth.path
# → submodule.libs/strutils.path
```

## Files

| File | Purpose |
|---|---|
| `.gitmono` | mono config (git config format, `[mono]` section) |
| `.gitmodules` | Standard Git submodule declarations |
| `<root>/<name>/` | Per-root submodule working directories |

## Cloning a mono repo

When cloning a mono-managed repo, alternates files are not preserved (they're in `.git/`, not tracked). After `git clone` + `git submodule update --init`:

```bash
# Regenerate alternates for all modules:
mono module tag auth v1.0.0   # auto-runs _setup_alternates before tagging
mono module version auth      # auto-runs _setup_alternates before resolving
```

Alternates are auto-regenerated on first `tag` or `version` command. For batch restoration, re-tag or re-version each module.

## Backward compatibility

Old `.gitmono` files with `mono.prefix` still work. The old `prefix` is treated as a single root and used as the default root. No migration needed.

## Manual removal

```bash
git submodule deinit -f <root>/<name>
git rm -f <root>/<name>
rm -rf .git/modules/<root>/<name>
git branch -D <root>/<name>/main
git tag -d <root>/<name>/root
git push origin --delete <root>/<name>/main 2>/dev/null || true
git push origin --delete <root>/<name>/root 2>/dev/null || true
```

## Under the hood: how tags cross module boundaries

Annotated tags created by `mono module tag` are stored at the parent level:

```
.git/refs/tags/modules/auth/v1.2.0
```

This is possible because of the alternates setup on `module add`. Without alternates, `git tag modules/auth/v1.2.0 <sha>` would fail with `fatal: bad object` — the commit object exists only in the submodule's object store.

The alternates files use **relative paths**, so they survive most directory moves. They must be regenerated after `git clone` (handled automatically on next `tag`/`version` command).

## Requirements

- git (any modern version, tested on 2.54+)
- bash

## License

MIT