#! /usr/bin/env bash
set -e

here="$(dirname "$(realpath "$0")")"
stack='abr'
dest=Default
dry_run='true'
profile=

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --dryrun flag
  --hot         Equivalent to --dry-run=false
  --stack       Defaults to '$stack'
  --dest      The place to upload to
  --key      The s3 object key (defaults to basename of src)
  --profile     The profile to use
  --help        This message
"
}

parse_arguments() {
  for opt in "$@"; do
    case ${opt} in
    --dry-run=*)
      if [ 'false' == "${opt#*=}" ]; then
        dry_run='false'
      fi
      ;;
    --stack=*)
      stack="${opt#*=}"
      ;;
    --key=*)
      key="${opt#*=}"
      ;;
    --hot)
      dry_run='false'
      ;;
    --dest=*)
      dest="${opt#*=}"
      ;;
    --profile=*)
      profile="${opt#*=}"
      ;;
    --help)
      display_help
      exit
      ;;
    *)
      display_help
      exit
      ;;
    esac
  done
}

get_distribution_nickname() {
  if [ "${1}" == 'Default' ]; then
    echo 'Primary'
    return
  fi
  echo "${1}"
}

main() {
  if ! [ -x "$(command -v jq)" ]; then
    echo 'exiting early: jq not installed'
    exit
  fi

  if [ '' == "${src}" ]; then
    echo 'a path to the src is required'
    exit
  fi

  if [ ! -f "${src}" ]; then
    echo "src is not a file. value submitted: ${src}"
    exit
  fi

  if [ -z "${key}" ]; then
    key="$(basename "$src")"
  fi

  if [ 'Default' != "${dest}" ] && [ "Website" != "${dest}" ]; then
    echo 'unsupported destination'
    exit
  fi

  # shellcheck source=/dev/null
  source "${here}/shared.bash" "${stack}"

  bucket_name=$(get_bucket_name "${dest}")

  if [ 'null' == "${bucket_name}" ]; then
    echo 'unable to determine bucket name'
    exit
  fi

checksumpath="${src}.checksum"
  if [ -f "${checksumpath}" ]; then
    checksum="$(cat "${checksumpath}")"
  else
    checksum="$(openssl dgst -sha256 -binary "${src}" | openssl enc -base64)"
    echo "${checksum}" > "${checksumpath}"
  fi

  head_object_response=$(
    
  aws s3api head-object \
    --bucket "${bucket_name}" \
    --key "${key}" \
    --checksum-mode ENABLED \
    --profile "${profile}" 2>&1 | sed '/^$/d'
  
  )
  
  domain_name=$(get_distribution_domain_name "$(get_distribution_nickname "${dest}")")
  alias=$(get_distribution_alias "$(get_distribution_nickname "${dest}")")

  if [ 'An error occurred (404) when calling the HeadObject operation: Not Found' == "${head_object_response}" ]; then
    args=( s3api put-object --bucket "${bucket_name}" --key "${key}" --body "$(realpath "${src}")" --checksum-sha256 "${checksum}" --content-type "$(file --mime-type "${src}" | rev | cut -d ':' -f 1 | rev)" --profile "${profile}" )
    cmd=( aws "${args[@]}" )

    if [ "${dry_run}" == 'true' ]; then
      echo 'dry run:' && printf '%q ' "${cmd[@]}" && echo ''
    else
      "${cmd[@]}"
      echo "abr: uploaded ${src} to s3://${bucket_name}/${key} with sha256 checksum ${checksum}"
      echo "abr: it is available here: https://${domain_name}/${key}"
      echo "abr: and here: https://${alias}/${key}"
      rm "${checksumpath}"
    fi

  elif [ "${checksum}" == "$(jq -r '.ChecksumSHA256' <<<"${head_object_response}")" ]; then
    echo 'refusing to upload identical object'
    echo "abr: it is available here: https://${domain_name}/${key}"
    echo "abr: and here: https://${alias}/${key}"
    exit
  else

    if [ "${dry_run}" == 'true' ]; then
      echo 'dry run:'
      printf '%q ' "${cmd[@]}"
      echo ''
    else
      "${cmd[@]}"
      echo "abr: uploaded ${src} to s3://$bucket_name/${key} with sha256 checksum ${checksum}"
      echo "abr: it is available here: https://${domain_name}/${key}"
      echo "abr: and here: https://${alias}/${key}"
      rm "${checksumpath}"
    fi
  fi
}

src="$1"
shift
parse_arguments "$@"

main
