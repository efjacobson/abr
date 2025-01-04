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

fresh_mjs='false'
images_mjs_path="${selfdir}/origin/images.mjs"
if [ ! -e "${images_mjs_path}" ]; then
    fresh_mjs='true'
    images="$(jq '.' <<< '[]')"
    while read -r img; do
        extension="${img##*.}"
        filename_without_extension="${img%.*}"
        filename_without_optimized="${filename_without_extension%.optimized}"
        original="${filename_without_optimized}.${extension}"
        path="image/$(basename "${original}")"
        images="$(jq --arg path "${path}" '. += [$path]' <<< "${images}")"
    done < <(find "${selfdir}/origin/image" -type f -name '*.optimized.jpg')
    echo "export default ${images}" > "${images_mjs_path}"
fi

while read -r tpl; do
        dest="${tpl%.*}"
        envsubst < "${tpl}" > "${dest}"
done < <(find "${selfdir}/origin" -type f -name "*.tpl")

cp "${selfdir}/origin/getOrigin.mjs" "${selfdir}/origin/getOrigin.mjs.bak"
echo "export default () => 'http://0.0.0.0:9000';" > "${selfdir}/origin/getOrigin.mjs"

python -m http.server 9000; cleanup_tpl && mv "${selfdir}/origin/getOrigin.mjs.bak" "${selfdir}/origin/getOrigin.mjs" && [[ "${fresh_mjs}" == 'true' ]] && rm "${images_mjs_path}"