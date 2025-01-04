#! /usr/bin/env bash
set -e

self="$0"
here="$(dirname "$(realpath "${self}")")"
cd "${here}" || exit

lock="${here}/cron.lock"
[ -f "${lock}" ] && echo "$(whoami) running at $(date) (locked)" >> "${logfile}" && exit
touch "${lock}"

logfile="${here}/cron.log"
echo "$(whoami) running at $(date)" >> "${logfile}"

code='abr-main'
profile='awsuploader'

trap 'rm -rf "${here}/$code" "${here}/${code}.zip"' EXIT

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

while read -r item; do
  if [ ! -f "${code}.zip" ]; then
    wget -O "${code}.zip" https://github.com/efjacobson/abr/archive/refs/heads/main.zip
    7z x "${code}.zip"
  fi

  rpath="$(realpath "${item}")"
  pattern="${here}/hot/"
  key=${rpath/$pattern/}

  args=( "${rpath}" --hot "--profile=${profile}" "--key=${key}" )
  cmd=( "./${code}/upload.bash" "${args[@]}" )
  printf '%q ' "${cmd[@]}" >> "${logfile}"
  echo "" >> "${logfile}"
  "${cmd[@]}" >> "${logfile}"

  rm "${item}"
done < <(find hot -type f ! -name "*.checksum")

rm "${lock}"
