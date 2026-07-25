#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

case $# in
  0)
    mode=run
    ;;
  1)
    case $1 in
      serialize|generate|run|dev|build|test)
        mode=$1
        ;;
      *)
        echo "Usage: ./app.sh [serialize|generate|run|dev|build|test]" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "Usage: ./app.sh [serialize|generate|run|dev|build|test]" >&2
    exit 2
    ;;
esac

case $mode in
  serialize|generate|run)
    nim c --threads:on main.nim
    exec ./main "$mode"
    ;;
  dev)
    exec "$script_dir/app.sh" run
    ;;
  test)
    test_dir=$(mktemp -d "${TMPDIR:-/tmp}/nimri-test.XXXXXX")
    trap 'rm -rf "$test_dir"' EXIT

    for test_source in tests/test_nimri_rpc.nim \
        tests/test_frontend_bindings.nim; do
      test_name=${test_source##*/}
      test_name=${test_name%.nim}
      test_binary="$test_dir/$test_name"
      test_cache="$test_dir/nimcache/$test_name"

      nim c --threads:on --nimcache:"$test_cache" \
        -o:"$test_binary" "$test_source"
      "$test_binary"
    done
    ;;
  build)
    mkdir -p bin
    rm -rf bin/frontend
    build_dir=$(mktemp -d "${TMPDIR:-/tmp}/nimri-build.XXXXXX")
    trap 'rm -rf "$build_dir"' EXIT

    nim c --threads:on --nimcache:"$build_dir/nimcache-bootstrap" \
      -o:"$build_dir/main" main.nim
    "$build_dir/main" generate
    npm --prefix frontend run build

    nim c --threads:on -d:release --nimcache:"$build_dir/nimcache-release" \
      -o:bin/main main.nim
    ;;
esac
