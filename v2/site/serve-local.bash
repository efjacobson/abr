#! /usr/bin/env bash
# set -x

cleanup_tpl() {
    while read -r tpl; do
            dest="${tpl%.*}"
            rm "${dest}"
    done < <(find "${selfdir}/origin" -type f -name "*.tpl")
}

self="${BASH_SOURCE[0]}"
while [ -L "${self}" ]; do
    self_dir="$(cd -P "$(dirname "${self}")" >/dev/null 2>&1 && pwd)"
    self="$(readlink "${self}")"
    [[ ${self} != /* ]] && self="${self_dir}/${self}"
done
self="$(readlink -f "${self}")"
selfdir=$(dirname "${self}")

if [ -e "${selfdir}/.env" ]; then
    set -a
    source "${selfdir}/.env"
    set +a
fi

cd "${selfdir}/origin" || exit 1

fresh_json='false'
images_json_path="${selfdir}/origin/images.json"
if [ ! -e "${images_json_path}" ]; then
    fresh_json='true'
    images="$(jq '.' <<< '[]')"
    while read -r img; do
        path="image/$(basename "${img}")"
        images="$(jq --arg path "${path}" '. += [$path]' <<< "${images}")"
    done < <(find "${selfdir}/origin/image" -type f -name '*.optimized.jpg')
    echo "${images}" > "${images_json_path}"
fi

while read -r tpl; do
        dest="${tpl%.*}"
        envsubst < "${tpl}" > "${dest}"
done < <(find "${selfdir}/origin" -type f -name "*.tpl")

python -m http.server 9000; cleanup_tpl && [[ "${fresh_json}" == 'true' ]] && rm "${images_json_path}"