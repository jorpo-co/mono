# mono module remove — Plan

## Overview

Two modes: `--flatten` (absorb code into main) and `--destructive` (delete everything).

```
mono module remove <name>                                # error: requires --flatten or --destructive
mono module remove --flatten <name>                      # soak code into main, no prompt
mono module remove --destructive <name>                  # error: requires --force
mono module remove --destructive --force <name>          # delete everything, no prompt
mono module remove --destructive <name> --force          # same, flags in any order
```

---

## `--flatten`

Purpose: dissolve the submodule relationship, keep the code in main's tree.

### What it does

| Step | Command | Why |
|---|---|---|
| 1. Read pinned SHA | `git ls-tree HEAD <path>` | Log the flatten point |
| 2. Remove gitlink | `git rm --cached <path>` | Unregister submodule from index |
| 3. Restore files | `git checkout HEAD -- <path>` | Populate working tree with real files (git rm --cached leaves them as untracked) |
| 4. Remove .gitmodules entry | `git config --file .gitmodules --remove-section submodule.<path>` | No longer a submodule |
| 5. Remove embedded .git file | `rm -f <path>/.git` | Was a gitfile pointing to .git/modules/<path> |
| 6. Stage everything | `git add <path> .gitmodules` | New regular files ready for commit |
| 7. Commit | `git commit -m "flatten <path> into main (was at <tag or SHA>)"` | Record the flatten |
| 8. Deinit submodule git dir | `git submodule deinit -f <path>` | Clean up submodule working tree metadata |
| 9. Delete submodule git dir | `rm -rf .git/modules/<path>` | No orphan objects |

### Does NOT touch

- Orphan branch (`modules/auth/main`) — stays for history
- Any tags (`modules/auth/v*`) — stays for reference
- The commit history on the orphan branch — stays in the repo

### After flatten

```
repo/
├── modules/auth/                   # now regular files, no .git file
│   ├── x.txt
│   └── ...
├── refs/heads/modules/auth/main    # still exists (history preserved)
├── refs/tags/modules/auth/v1.0.0   # still exists (reference preserved)
```

---

## `--destructive`

Purpose: completely remove the module from the repo.

### What it does

| Step | Command | Why |
|---|---|---|
| 1. Deinit submodule | `git submodule deinit -f <path>` | Remove working tree |
| 2. Remove .gitmodules entry | `git config --file .gitmodules --remove-section submodule.<path>` | Unregister |
| 3. Remove from index | `git rm --cached <path>` | Unlink from tree |
| 4. Commit removal | `git commit -m "remove module <path>"` | Record the removal |
| 5. Delete orphan branch | `git branch -D <root>/<name>/<base>` | Destroy history |
| 6. Delete module root tag | `git tag -d <root>/<name>/v0.0.0` | Remove root marker |
| 7. Delete version tags | `git tag -l '<root>/<name>/v*' \| xargs git tag -d` | Remove all version tags |
| 8. Delete submodule git dir | `rm -rf .git/modules/<path>` | Remove object store |

### Requires `--force`

Without `--force`, print a warning listing everything that will be destroyed and abort:

```
Error: destructive remove will delete branch modules/auth/main,
tags modules/auth/v*, and all module objects.
Use --force to confirm.
```

### After destructive

```
repo/
├── modules/                        # empty (or removed)
├── refs/heads/modules/auth/main    # deleted
├── refs/tags/modules/auth/v1.0.0   # deleted
├── .git/modules/modules/auth/      # deleted
```

Commits on the orphan branch remain in the object store until `git gc` prunes them (unreachable). That's fine — they're truly gone after gc.

---

## Error cases

| Scenario | Behaviour |
|---|---|
| Module doesn't exist | Error: "module '<name>' not found in root '<root>'" |
| Working tree has unstaged changes | Error: "uncommitted changes in '<path>'. Commit or stash first." |
| `--destructive` without `--force` | Error + list of what will be destroyed, exit 1 |
| Both `--flatten` and `--destructive` | Error: "cannot use both --flatten and --destructive" |
| Neither flag | Error: "must specify --flatten or --destructive" |

---

## Tests needed

| Test | Checks |
|---|---|
| `module remove --flatten <name>` | Files remain in tree, no .git file, no .gitmodules entry, branch still exists |
| `module remove --flatten` without name | Usage error |
| `module remove --destructive --force <name>` | Branch deleted, tags deleted, .gitmodules entry removed |
| `module remove --destructive` without `--force` | Error message with destroy list, exit 1 |
| `module remove` without flag | Error: requires --flatten or --destructive |
| `module remove --flatten` then `module tag` on same name | Fails — submodule no longer registered |
| `module remove --destructive --force` on non-existent module | Error: not found |
| Flatten preserves commit history | `git log modules/auth/main` still works after flatten |

---

## Implementation order

1. `_usage_module_remove` + flag parsing (`--flatten`, `--destructive`, `--force`)
2. `_flatten_module` — submodule → regular files
3. `_destroy_module` — delete everything
4. Wire into `mono_module_remove` dispatch
5. Tests