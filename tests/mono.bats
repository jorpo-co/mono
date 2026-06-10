#!/usr/bin/env bats

setup() {
  export TMPDIR=$(mktemp -d /tmp/mono-test-XXXXXX)
  export MONO="$BATS_TEST_DIRNAME/../mono"
}

teardown() {
  rm -rf "$TMPDIR"
}

# ---- helpers ----

assert_config() {
  run git config -f .gitmono "$1"
  [ "$output" = "$2" ]
}

_init_repo() {
  cd "$TMPDIR"
  rm -rf working
  git init --bare origin.git >/dev/null 2>&1
  git clone origin.git working >/dev/null 2>&1
  cd working
  "$MONO" init "$@" >/dev/null 2>&1
}

# ---- mono: no args ----

@test "no args prints usage and exits 1" {
  run "$MONO"
  [ "$status" -eq 1 ]
  [ "$output" = "No arguments supplied" ]
}

# ---- init ----

@test "init on fresh repo creates default config" {
  _init_repo
  assert_config mono.roots "modules"
  assert_config mono.default-root "modules"
  assert_config mono.base "main"
}

@test "init --roots sets roots and default-root" {
  _init_repo --roots modules,libs
  assert_config mono.roots "modules,libs"
  assert_config mono.default-root "modules"
}

@test "init -r shorthand works" {
  _init_repo -r libs,plugins
  assert_config mono.roots "libs,plugins"
  assert_config mono.default-root "libs"
}

@test "init --roots --default-root overrides default" {
  _init_repo --roots modules,libs --default-root libs
  assert_config mono.roots "modules,libs"
  assert_config mono.default-root "libs"
}

@test "init --help prints usage and exits 0" {
  cd "$TMPDIR"
  mkdir fresh && cd fresh
  run "$MONO" init --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "init on repo with commits bails out" {
  cd "$TMPDIR"
  mkdir hascommits && cd hascommits
  git init >/dev/null 2>&1
  git commit --allow-empty -m "first" >/dev/null 2>&1

  run "$MONO" init
  [ "$status" -eq 0 ]
  [ ! -f .gitmono ]
}

# ---- config ----

@test "config reads existing key" {
  _init_repo
  run "$MONO" config mono.roots
  [ "$status" -eq 0 ]
  [ "$output" = "modules" ]
}

@test "config writes and reads back" {
  _init_repo
  run "$MONO" config mono.roots modules,libs,plugins
  [ "$status" -eq 0 ]
  run "$MONO" config mono.roots
  [ "$output" = "modules,libs,plugins" ]
}

@test "config --root-list prints roots" {
  _init_repo --roots modules,libs
  run "$MONO" config --root-list
  [ "$output" = "modules libs" ]
}

@test "config --default-root prints default root" {
  _init_repo --roots modules,libs --default-root libs
  run "$MONO" config --default-root
  [ "$output" = "libs" ]
}

# ---- module (list) ----

@test "module with no modules prints nothing" {
  _init_repo
  run "$MONO" module
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "module with modules lists submodule paths" {
  _init_repo --roots modules,libs
  "$MONO" module add auth >/dev/null 2>&1
  "$MONO" module add -r libs strutils >/dev/null 2>&1

  run "$MONO" module
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth" ]]
  [[ "$output" =~ "libs/strutils" ]]
}

# ---- module add ----

@test "module add creates submodule under default root" {
  _init_repo
  run "$MONO" module add auth
  [ "$status" -eq 0 ]

  run git config --file .gitmodules --get submodule.modules/auth.path
  [ "$output" = "modules/auth" ]

  run git show-ref --verify refs/heads/modules/auth/main
  [ "$status" -eq 0 ]

  run git show-ref --verify refs/tags/modules/auth/v0.0.0
  [ "$status" -eq 0 ]
}

@test "module add -r creates submodule under specified root" {
  _init_repo --roots modules,libs
  run "$MONO" module add -r libs strutils
  [ "$status" -eq 0 ]

  run git config --file .gitmodules --get submodule.libs/strutils.path
  [ "$output" = "libs/strutils" ]

  run git show-ref --verify refs/heads/libs/strutils/main
  [ "$status" -eq 0 ]
}

@test "module add with full path creates submodule" {
  _init_repo --roots modules,libs
  run "$MONO" module add libs/strutils
  [ "$status" -eq 0 ]

  run git config --file .gitmodules --get submodule.libs/strutils.path
  [ "$output" = "libs/strutils" ]

  run git show-ref --verify refs/heads/libs/strutils/main
  [ "$status" -eq 0 ]
}

@test "module add with ambiguous -r and path fails" {
  _init_repo
  run "$MONO" module add -r modules modules/auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ambiguous" ]]
}

@test "module add with invalid root in path fails" {
  _init_repo
  run "$MONO" module add nonexistent/auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "nonexistent" ]]
}

@test "module add with no name prints usage and exits 1" {
  _init_repo
  run "$MONO" module add
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "module add --help prints usage and exits 0" {
  _init_repo
  run "$MONO" module add --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "module add with invalid root fails" {
  _init_repo
  run "$MONO" module add -r nonexistent bad
  [ "$status" -ne 0 ]
  [[ "$output" =~ "nonexistent" ]]
}

@test "module add without init fails" {
  cd "$TMPDIR"
  mkdir fresh && cd fresh
  git init >/dev/null 2>&1
  git commit --allow-empty -m "first" >/dev/null 2>&1

  run "$MONO" module add auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not at repo root" ]]
}

@test "module add duplicate fails" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  run "$MONO" module add auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "already exists" ]]
}

# ---- module add: alternates ----

@test "module add sets up bidirectional alternates" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  # parent alternates should reference submodule objects
  run cat .git/objects/info/alternates
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/objects" ]]

  # submodule alternates should reference parent objects
  run cat .git/modules/modules/auth/objects/info/alternates
  [ "$status" -eq 0 ]
  [[ "$output" =~ "objects" ]]
}

@test "alternates allow parent to read submodule commit" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  # commit in submodule
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  SHA=$(git rev-parse HEAD)
  cd ../..

  # parent should be able to read the object via alternates
  run git cat-file -t "$SHA"
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]
}

# ---- module tag ----

@test "module tag creates annotated parent-level tag" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  # commit in submodule
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  SHA=$(git rev-parse HEAD)
  cd ../..

  run "$MONO" module tag modules/auth v1.0.0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Tagged" ]]

  # tag exists in parent
  run git tag -l
  [[ "$output" =~ "modules/auth/v1.0.0" ]]

  # tag resolves to correct commit
  run git rev-parse modules/auth/v1.0.0^{commit}
  [ "$output" = "$SHA" ]

  # parent branch ref was updated
  run git rev-parse modules/auth/main
  [ "$output" = "$SHA" ]

  # pinned in main tree
  run git ls-tree HEAD modules/auth
  [[ "$output" =~ "$SHA" ]]
}

@test "module tag with explicit root path" {
  _init_repo --roots modules,libs
  "$MONO" module add -r libs strutils >/dev/null 2>&1

  cd libs/strutils
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  SHA=$(git rev-parse HEAD)
  cd ../..

  run "$MONO" module tag libs/strutils v0.5.0
  [ "$status" -eq 0 ]

  run git tag -l
  [[ "$output" =~ "libs/strutils/v0.5.0" ]]

  run git rev-parse libs/strutils/v0.5.0^{commit}
  [ "$output" = "$SHA" ]
}

@test "module tag --help prints usage" {
  _init_repo
  run "$MONO" module tag --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "module tag with no name or version fails" {
  _init_repo
  run "$MONO" module tag
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage:" ]]

  run "$MONO" module tag modules/auth
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "module tag on non-existent module fails" {
  _init_repo
  run "$MONO" module tag modules/auth v1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}
@test "module tag with bare name uses default root" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  cd ../..
  run "$MONO" module tag auth v1.0.0
  [ "$status" -eq 0 ]
  run git tag -l
  [[ "$output" =~ "modules/auth/v1.0.0" ]]
}

@test "module tag with invalid root fails" {
  _init_repo
  run "$MONO" module tag nonexistent/auth v1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "nonexistent" ]]
}

@test "module tag without init fails" {
  cd "$TMPDIR"
  mkdir fresh && cd fresh
  git init >/dev/null 2>&1
  git commit --allow-empty -m "first" >/dev/null 2>&1

  run "$MONO" module tag modules/auth v1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not at repo root" ]]
}

# ---- module version ----

@test "module version shows tag for pinned module" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  SHA=$(git rev-parse HEAD)
  cd ../..

  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1

  run "$MONO" module version modules/auth
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/v1.0.0" ]]
  [[ "$output" =~ "$SHA" ]]
}

@test "module version shows SHA when no tag" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  # commit but don't tag
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  SHA=$(git rev-parse HEAD)
  cd ../..
  git add modules/auth
  git commit -m "update" >/dev/null 2>&1

  run "$MONO" module version modules/auth
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$SHA" ]]
  [[ "$output" =~ "no tag" ]]
}

@test "module version --help prints usage" {
  _init_repo
  run "$MONO" module version --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "module version with no path fails" {
  _init_repo
  run "$MONO" module version
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "module version with bare name uses default root" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1
  SHA=$(git rev-parse HEAD)
  cd ../..
  git add modules/auth
  git commit -m "update" >/dev/null 2>&1
  run "$MONO" module version auth
  [ "$status" -eq 0 ]
  [[ "$output" =~ "no tag" ]]
}

@test "module version on unadded module fails" {
  _init_repo
  run "$MONO" module version modules/auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

# ---- module remove ----

@test "module remove prints not implemented" {
  _init_repo
  run "$MONO" module remove
  [ "$status" -eq 0 ]
  [ "$output" = "module remove not implemented yet" ]
}

# ---- edge cases ----

@test "module with unknown subcommand prints nothing" {
  _init_repo
  run "$MONO" module unknown
  [ "$status" -eq 0 ]
}

@test "full lifecycle: init, add, work, tag, version" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  cd modules/auth
  echo "code" > main.go
  git add main.go
  git commit -m "feat: initial" >/dev/null 2>&1
  cd ../..

  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1

  run "$MONO" module version modules/auth
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/v1.0.0" ]]

  run git tag -l
  [[ "$output" =~ "modules/auth/v1.0.0" ]]

  run git describe --tags --abbrev=0 2>/dev/null || true
}
# ---- running from inside submodule ----

@test "module tag from inside submodule fails" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "new" >/dev/null 2>&1

  run "$MONO" module tag modules/auth v1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not at repo root" ]]
  cd ../..
}

@test "module add from inside submodule fails" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  cd modules/auth
  run "$MONO" module add api
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not at repo root" ]]
  cd ../..
}

@test "module version from inside submodule fails" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1

  cd modules/auth
  run "$MONO" module version modules/auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not at repo root" ]]
  cd ../..
}


# ---- clone ----

@test "clone with no modules succeeds" {
  _init_repo
  run "$MONO" clone
  [ "$status" -eq 0 ]
}

@test "clone --help prints usage" {
  _init_repo
  run "$MONO" clone --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "clone checks out submodules and sets up alternates" {
  cd "$TMPDIR"
  rm -rf source
  git init --bare source.git >/dev/null 2>&1
  git clone source.git source >/dev/null 2>&1
  cd source
  "$MONO" init >/dev/null 2>&1
  "$MONO" module add auth >/dev/null 2>&1
  echo "data" > modules/auth/x.txt
  cd modules/auth
  git add x.txt
  git commit -m "feat" >/dev/null 2>&1
  cd ../..
  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1

  # Push everything
  git push origin main 2>/dev/null
  git push origin modules/auth/main 2>/dev/null
  git push origin --tags 2>/dev/null

  # Clone fresh and run mono clone
  cd "$TMPDIR"
  rm -rf fresh
  git clone source.git fresh >/dev/null 2>&1
  cd fresh

  run "$MONO" clone
  [ "$status" -eq 0 ]

  # Submodule checked out
  [ -f modules/auth/x.txt ]

  # Alternates set up
  run cat .git/objects/info/alternates
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/objects" ]]
}

# ---- setup ----

@test "setup --help prints usage" {
  _init_repo
  run "$MONO" setup --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "setup with no submodules succeeds" {
  _init_repo
  run "$MONO" setup
  [ "$status" -eq 0 ]
}

@test "setup switches submodule to tracked branch after clone" {
  cd "$TMPDIR"
  rm -rf source
  git init --bare source.git >/dev/null 2>&1
  git clone source.git source >/dev/null 2>&1
  cd source
  "$MONO" init >/dev/null 2>&1
  "$MONO" module add auth >/dev/null 2>&1
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "feat" >/dev/null 2>&1
  cd ../..
  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1
  git push origin main 2>/dev/null
  git push origin modules/auth/main 2>/dev/null
  git push origin --tags 2>/dev/null

  # Clone fresh — submodule will be in detached HEAD
  cd "$TMPDIR"
  rm -rf fresh
  git clone source.git fresh >/dev/null 2>&1
  cd fresh
  git submodule update --init --recursive >/dev/null 2>&1

  # Verify detached HEAD before setup
  cd modules/auth
  run git symbolic-ref HEAD
  [ "$status" -ne 0 ]
  cd ../..

  # Run setup
  run "$MONO" setup
  [ "$status" -eq 0 ]

  # Verify submodule is now on its tracked branch
  cd modules/auth
  run git symbolic-ref HEAD
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/main" ]]
}

@test "setup is idempotent" {
  cd "$TMPDIR"
  rm -rf source
  git init --bare source.git >/dev/null 2>&1
  git clone source.git source >/dev/null 2>&1
  cd source
  "$MONO" init >/dev/null 2>&1
  "$MONO" module add auth >/dev/null 2>&1
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "feat" >/dev/null 2>&1
  cd ../..
  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1
  git push origin main 2>/dev/null
  git push origin modules/auth/main 2>/dev/null
  git push origin --tags 2>/dev/null

  cd "$TMPDIR"
  rm -rf fresh
  git clone source.git fresh >/dev/null 2>&1
  cd fresh
  git submodule update --init --recursive >/dev/null 2>&1

  # Run setup twice
  "$MONO" setup >/dev/null 2>&1
  run "$MONO" setup
  [ "$status" -eq 0 ]

  # Still on tracked branch after second run
  cd modules/auth
  run git symbolic-ref HEAD
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/main" ]]
}

@test "clone delegates to setup (branch checkout)" {
  cd "$TMPDIR"
  rm -rf source
  git init --bare source.git >/dev/null 2>&1
  git clone source.git source >/dev/null 2>&1
  cd source
  "$MONO" init >/dev/null 2>&1
  "$MONO" module add auth >/dev/null 2>&1
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "feat" >/dev/null 2>&1
  cd ../..
  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1
  git push origin main 2>/dev/null
  git push origin modules/auth/main 2>/dev/null
  git push origin --tags 2>/dev/null

  cd "$TMPDIR"
  rm -rf fresh
  git clone source.git fresh >/dev/null 2>&1
  cd fresh

  # mono clone should leave submodule on tracked branch (not detached)
  "$MONO" clone >/dev/null 2>&1

  cd modules/auth
  run git symbolic-ref HEAD
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth/main" ]]
}

# ---- push ----

@test "push --help prints usage" {
  _init_repo
  run "$MONO" push --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "push with no modules pushes main" {
  cd "$TMPDIR"
  rm -rf source
  git init --bare source.git >/dev/null 2>&1
  git clone source.git work >/dev/null 2>&1
  cd work
  "$MONO" init >/dev/null 2>&1

  # Make a commit so push has something to send
  echo "readme" > README.md
  git add README.md
  git commit -m "init" >/dev/null 2>&1

  run "$MONO" push
  [ "$status" -eq 0 ]
  [[ "$output" =~ "main" ]]
}

@test "push pushes main, module branches, and tags" {
  cd "$TMPDIR"
  rm -rf source
  git init --bare source.git >/dev/null 2>&1
  git clone source.git source >/dev/null 2>&1
  cd source
  "$MONO" init >/dev/null 2>&1
  "$MONO" module add auth >/dev/null 2>&1
  cd modules/auth
  echo "data" > x.txt
  git add x.txt
  git commit -m "feat" >/dev/null 2>&1
  cd ../..
  "$MONO" module tag modules/auth v1.0.0 >/dev/null 2>&1

  run "$MONO" push
  [ "$status" -eq 0 ]
  [[ "$output" =~ "main" ]]
  [[ "$output" =~ "modules/auth/main" ]]
  [[ "$output" =~ "modules/auth/v1.0.0" ]]

  # Verify on the remote
  run git ls-remote origin refs/heads/main
  [ "$status" -eq 0 ]
  [[ "$output" =~ "refs/heads/main" ]]

  run git ls-remote origin refs/heads/modules/auth/main
  [ "$status" -eq 0 ]
  [[ "$output" =~ "refs/heads/modules/auth/main" ]]

  run git ls-remote origin refs/tags/modules/auth/v1.0.0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "refs/tags/modules/auth/v1.0.0" ]]
}

@test "push without origin warns but exits 0" {
  cd "$TMPDIR"
  mkdir noremote && cd noremote
  git init >/dev/null 2>&1
  "$MONO" init >/dev/null 2>&1
  run "$MONO" push
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Warning" ]]
}

# ---- Phase 1: cleanup - root tag, quoting, no auto-push, walk-up ----

@test "no args prints usage to stderr" {
  run "$MONO"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No arguments supplied" ]]
}

@test "init creates v0.0.0 root tag" {
  cd "$TMPDIR"
  mkdir fresh && cd fresh
  git init >/dev/null 2>&1
  "$MONO" init >/dev/null 2>&1
  run git rev-parse v0.0.0
  [ "$status" -eq 0 ]
}

@test "module add without remote does not fail" {
  cd "$TMPDIR"
  mkdir noremote && cd noremote
  git init >/dev/null 2>&1
  "$MONO" init >/dev/null 2>&1
  run "$MONO" module add auth
  [ "$status" -eq 0 ]
}

@test "module list works from subdirectory" {
  _init_repo
  "$MONO" module add auth >/dev/null 2>&1
  mkdir subdir
  cd subdir
  run "$MONO" module
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth" ]]
}

# ---- multiple modules ----

@test "adding two modules preserves both in .gitmodules" {
  _init_repo --roots modules,libs
  "$MONO" module add auth >/dev/null 2>&1
  run "$MONO" module add -r libs strutils
  [ "$status" -eq 0 ]

  run git config --file .gitmodules --get-regexp path
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth" ]]
  [[ "$output" =~ "libs/strutils" ]]
}


@test "add 5 modules with mixed syntax preserves all entries" {
  _init_repo --roots modules,libs,plugins
  run "$MONO" module add modules/auth
  [ "$status" -eq 0 ]
  run "$MONO" module add -r libs strutils
  [ "$status" -eq 0 ]
  run "$MONO" module add plugins/slack
  [ "$status" -eq 0 ]
  run "$MONO" module add modules/api
  [ "$status" -eq 0 ]
  run "$MONO" module add libs/utils
  [ "$status" -eq 0 ]

  run git config --file .gitmodules --get-regexp path
  [ "$status" -eq 0 ]
  [[ "$output" =~ "modules/auth" ]]
  [[ "$output" =~ "libs/strutils" ]]
  [[ "$output" =~ "plugins/slack" ]]
  [[ "$output" =~ "modules/api" ]]
  [[ "$output" =~ "libs/utils" ]]

  [ -f modules/auth/.git ]
  [ -f libs/strutils/.git ]
  [ -f plugins/slack/.git ]
  [ -f modules/api/.git ]
  [ -f libs/utils/.git ]
}
