#! /bin/bash

here="$(dirname "$(realpath "$0")")"
stack='abr'
bucket=default
dry_run=true
profile=

display_help() {
  echo "
Available options:
  --dry-run     Deploy as a dry run, aka the --dryrun flag
  --hot         Equivalent to --dry-run=false
  --stack       Defaults to '$stack'
  --bucket      The bucket to upload to
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
        dry_run=false
      fi
      ;;
    --stack=*)
      stack="${opt#*=}"
      ;;
    --key=*)
      key="${opt#*=}"
      ;;
    --hot)
      dry_run=false
      ;;
    --bucket=*)
      bucket="${opt#*=}"
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

main() {
  if ! [ -x "$(command -v jq)" ]; then
    echo 'exiting early: jq not installed'
    exit
  fi

  if [ '' == "$src" ]; then
    echo 'a path to the src is required'
    exit
  fi

  if [ ! -f "$src" ]; then
    echo 'src is not a file'
    exit
  fi

  if [ -z "$key" ]; then
    key="$(basename "$src")"
  fi

  if [ 'default' != "$bucket" ]; then
    echo 'non-default uploads are not currently supported'
    exit
  fi

  # shellcheck source=/dev/null
  source "$here/shared.bash" "$stack"

  bucket_name=$(get_bucket_name 'Default')

  if [ 'null' == "$bucket_name" ]; then
    echo 'unable to determine bucket name'
    exit
  fi

  checksum="$(openssl dgst -sha256 -binary "$src" | openssl enc -base64)"

  head_object_response=$(aws s3api head-object \
    --bucket "$bucket_name" \
    --key "$key" \
    --checksum-mode ENABLED \
    --profile "$profile" 2>&1 | sed '/^$/d')

  if [ 'An error occurred (404) when calling the HeadObject operation: Not Found' == "$head_object_response" ]; then
    cmd="aws s3api put-object \
      --bucket $bucket_name \
      --key "$key" \
      --body $(realpath "$src") \
      --checksum-sha256 $checksum \
      --content-type $(file --mime-type "$src" | cut -d' ' -f2) \
      --profile $profile"
    $dry_run && echo "dry run: $cmd"
    $dry_run || eval "$cmd" >>/dev/null
    echo "abr: uploaded $src to s3://$bucket/$(basename "$src") with sha256 checksum $checksum"
    echo "abr: it is available here: https://$(get_distribution_domain_name 'Primary')/$(basename "$src")"
  elif [ "$checksum" == "$(jq -r '.ChecksumSHA256' <<<"$head_object_response")" ]; then
    echo 'refusing to upload identical object'
    echo "abr: it is available here: https://$(get_distribution_domain_name 'Primary')/$(basename "$src")"
    exit
  else
    cmd="aws s3api put-object \
      --bucket $bucket_name \
      --key "$key" \
      --body $(realpath "$src") \
      --checksum-sha256 $checksum \
      --content-type $(file --mime-type "$src" | cut -d' ' -f2) \
      --profile $profile"
    $dry_run && echo "dry run: $cmd"
    $dry_run || eval "$cmd" >>/dev/null

    # aws s3api put-object \
    #   --bucket "$bucket_name" \
    #   --key "$(basename "$src")" \
    #   --body "$src" \
    #   --checksum-sha256 "$checksum" \
    #   --profile "$profile" >>/dev/null
    echo "abr: uploaded $src to s3://$bucket/$(basename "$src") with sha256 checksum $checksum"
    echo "abr: it is available here: https://$(get_distribution_domain_name 'Primary')/$(basename "$src")"
  fi

  #PrimaryDistributionDomainName

  #   if jq -e . >/dev/null 2>&1 <<<"$head_object_response"; then
  #   echo "$head_object_response"
  #   echo "$checksum"
  #       echo 'refusing to upload object that already exists in the bucket'
  #       exit
  #   fi


  # dest="s3://$bucket_name"
  # cmd="aws s3 cp $src $dest/$src --profile $profile --checksum-sha256 $checksum"

  # if $dry_run; then
  #   cmd+=' --dryrun'
  # fi

  # eval "$cmd"
}

src="$1"
shift
parse_arguments "$@"

main
