#! /bin/bash

self="$0"
here="$(dirname "$(realpath "$self")")"
cd "$here" || exit
code='abr-main'
profile='awsuploader'

trap 'rm -rf "$here/$code" "$here/$code.zip"' EXIT

for opt in "$@"; do
  case ${opt} in
  --profile=*)
    profile="${opt#*=}"
    ;;
  *)
    exit
    ;;
  esac
done

selfbase="$(basename "$self")"
for item in ./*; do
  [ ! -f "$item" ] && continue

  case "$(basename "$item")" in
    "$selfbase"|'README.md'|"$code"|"$code.zip")
    continue
    ;;
  esac

  if [ ! -d "$code" ]; then
    wget -O "$code.zip" https://github.com/efjacobson/abr/archive/refs/heads/main.zip
    7z x "$code.zip"
  fi

  "./$code/upload.bash" "$(basename "$item")" --profile="$profile" --hot
  rm "$item"
done

# sleep 10

# rm -rf "$code" "$code.zip"