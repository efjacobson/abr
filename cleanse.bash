#! /usr/bin/env bash

account_id=
region=
profile=
regions=()

here="$(dirname "$(realpath "$0")")"
readonly here

display_help() {
  echo "
Available options:
  --account_id  Your AWS account id
  --help        This message
"
}

for opt in "$@"; do
  case ${opt} in
  --account_id=*)
    account_id="${opt#*=}"
    ;;
  --regions=*)
    IFS=',' read -ra regions <<<"${opt#*=}"
    ;;
  --help)
    display_help
    exit
    ;;
  *)
    echo "unknown option: '${opt}'"
    display_help
    exit
    ;;
  esac
done

cleanse_region() {
  region="$1"
  get_resources_response=$(aws resourcegroupstaggingapi get-resources \
    --profile "$profile" \
    --region="$region" 2>&1 | sed '/^$/d')
  if [ -n "$(jq '.' <<<"$get_resources_response" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
    echo "$get_resources_response"
    echo 'abr: something went wrong ^^'
    exit
  fi

  while read -r arn; do
    regex="^arn:aws:lambda:$region:$account_id:function.+"
    if [[ "$arn" =~ $regex ]]; then
      aws lambda delete-function \
        --function-name "$arn" \
        --region "$region" \
        --profile "$profile"
    else
      echo "unsupported arn: $arn"
    fi
  done < <(jq -r '.ResourceTagMappingList[] | .ResourceARN' <<<"$get_resources_response")

  echo "done: $region"
}

main() {
  if [ 0 -eq ${#regions[@]} ]; then
    describe_regions_response=$(aws ec2 describe-regions \
      --profile "$profile" \
      --region "$region" 2>&1 | sed '/^$/d')
    if [ -n "$(jq '.' <<<"$describe_regions_response" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
      echo "$describe_regions_response"
      echo 'abr: something went wrong ^^'
      exit
    fi

    while read -r region; do
      cleanse_region "$region"
    done < <(jq -r '.Regions[] | .RegionName' <<<"$describe_regions_response")
  else
    for region in "${regions[@]}"; do
      cleanse_region "$region"
    done
  fi
}

# shellcheck source=/dev/null
source "$here/shared.bash"
main
