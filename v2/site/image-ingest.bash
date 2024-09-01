#! /usr/bin/env bash
# set -x

main() {
    local self=
    local selfdir=
    self="${BASH_SOURCE[0]}"
    while [ -L "${self}" ]; do
        self_dir="$(cd -P "$(dirname "${self}")" >/dev/null 2>&1 && pwd)"
        self="$(readlink "${self}")"
        [[ ${self} != /* ]] && self="${self_dir}/${self}"
    done
    self="$(readlink -f "${self}")"
    selfdir=$(dirname "${self}")
    ingestdir="${selfdir}/ingest"

    if [ ! -d "${ingestdir}" ]; then
        echo "you need to put some images in $(realpath "${ingestdir}")"
        exit 1
    fi

    step_0_dir="${selfdir}/ingest.0"

    if ! [ -d "${step_0_dir}" ]; then
        step_0
    fi

    step_1_dir="${selfdir}/ingest.1"

    if ! [ -d "${step_1_dir}" ]; then
        step_1
    fi

    step_2_dir="${selfdir}/ingest.2"

    if ! [ -d "${step_2_dir}" ]; then
        step_2
    fi
}

step_0() {
    cp -r "${ingestdir}" "${step_0_dir}"

    find "${step_0_dir}/" -type f -exec exiftool -all= --icc_profile:all {} \;
    find "${step_0_dir}/" -type f -name "*_original" -exec rm -f {} \;
    echo "now fix the orientation of the images in $(realpath "${step_0_dir}") (before running the command again)"
    exit 1
}

step_1() {
    cp -r "${step_0_dir}" "${step_1_dir}"

    local extension=
    local checksumish=
    local newfile=
    for file in "${step_1_dir}"/*; do
        extension="${file##*.}"
        case "${extension}" in
            jpg|jpeg|png)
                ;;
            *)
                continue
                ;;
        esac
        checksumish="$(openssl dgst -sha256 -binary "${file}" | openssl enc -base64 | base64)"
        newfile="${step_1_dir}/${checksumish}.${extension}"
        mv "${file}" "${newfile}"
    done
}

step_2() {
    cp -r "${step_1_dir}" "${step_2_dir}"

    local filename=
    local extension=
    local filename_without_extension=
    local optimized=
    for file in "${step_2_dir}"/*; do
        filename="$(basename -- "$file")"
        extension="${filename##*.}"
        filename_without_extension="${filename%.*}"
        case "${extension}" in
            jpg|jpeg|png)
                ;;
            *)
                continue
                ;;
        esac

        optimized="${step_2_dir}/${filename_without_extension}.optimized.${extension}"
        convert "${file}" -sampling-factor 4:2:0 -strip -quality 85 -interlace Plane -gaussian-blur 0.05 "${optimized}"

        optimized_size="$(du "${optimized}" | cut -f 1)"
        file_size="$(du "${file}" | cut -f 1)"

        if [[ "${optimized_size}" -ge "${file_size}" ]]; then
            mv "${optimized}" "${optimized}.bak"
            cp "${file}" "${optimized}"
        fi
    done
}

main