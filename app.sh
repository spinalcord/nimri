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
      serialize|generate|run|dev|build)
        mode=$1
        ;;
      *)
        echo "Usage: ./app.sh [serialize|generate|run|dev|build]" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "Usage: ./app.sh [serialize|generate|run|dev|build]" >&2
    exit 2
    ;;
esac

case $mode in
  serialize|generate|run)
    nim c main.nim
    exec ./main "$mode"
    ;;
  dev)
    exec "$script_dir/app.sh" run
    ;;
  build)
    mkdir -p bin
    nim c -d:release -o:bin/main main.nim
    ./bin/main generate
    npm --prefix frontend run build

    rm -rf bin/frontend
    cp -R frontend/dist bin/frontend
    ;;
esac
