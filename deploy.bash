#! /bin/bash

config_file=
region=
stack_name=
here="$(dirname "$(realpath "$0")")"

# shellcheck source=/dev/null
source "$here/shared.bash"

template="$here/infra.yaml"
deploy_template=$(mktemp)
json_config=

default_aws_arguments="--region $region --profile personal"

dry_run=true

display_help() {
  echo "
Available options:
  --dry-run     When true, no changes are actually made
  --hot         Equivalent to --dry-run=false
  --help        This message
"
}

for opt in "$@"; do
  case ${opt} in
  --dry-run=*)
    if [ 'false' == "${opt#*=}" ]; then
      dry_run=false
    fi
    ;;
  --hot)
    dry_run=false
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

create_deploy_template() {
  local AWSS3Bucket_output_GetAtt_fields=('Arn' 'DomainName' 'DualStackDomainName' 'RegionalDomainName' 'WebsiteURL')
  local AWSCloudFrontDistribution_output_GetAtt_fields=('DomainName' 'Id')
  local AWSCloudFrontCloudFrontOriginAccessIdentity_output_GetAtt_fields=('Id' 'S3CanonicalUserId')
  local AWSLogsLogGroup_output_GetAtt_fields=('Arn')
  local AWSServerlessFunction_output_GetAtt_fields=('Arn')
  local AWSLambdaFunction_output_GetAtt_fields=('Arn')
  local AWSIAMRole_output_GetAtt_fields=('Arn' 'RoleId')

  local temp_file_0 && temp_file_0="$(mktemp)"
  echo '{}' >"$temp_file_0"
  local outputs && outputs=$(echo '{}' | jq)
  yq '.Resources | keys[]' "$template" | while read -r resource; do
    local raw_resource && raw_resource=$(echo "$resource" | sed 's/"//g')
    local Ref_filter=". + {\"${raw_resource}Ref\": {\"Value\": \"!Ref $raw_resource\"}}"
    outputs=$(echo "$outputs" | jq "$Ref_filter")
    local filter=".Resources.$raw_resource.Type"
    local type && type=$(yq -r "$filter" "$template")
    local config=${type//:/}
    local output_fields="$config"_output_GetAtt_fields[@]
    local count=0
    for GetAtt_field in ${!output_fields}; do
      GetAtt_filter=". + {\"$raw_resource$GetAtt_field\": {\"Value\": \"!GetAtt $raw_resource.$GetAtt_field\"}}"
      outputs=$(echo "$outputs" | jq "$GetAtt_filter")
      count=$((count + 1))
    done
    if [ "$count" == 0 ] && [ 'AWSS3BucketPolicy' != "$config" ]; then
      echo "no config for $config!"
    fi
    local insert_filter=". + {\"Outputs\":$outputs}"
    local result && result=$(cat "$temp_file_0" | yq "$insert_filter")
    echo "$result" >"$temp_file_0"
  done
  local final_outputs && final_outputs=$(cat "$temp_file_0" | yq -y | sed -E 's/(Value: '\'')/Value: /g' | sed -E 's/^(.+)Value(.+)('\'')$/\1Value\2/g')
  echo "$final_outputs" >"$temp_file_0"
  cp "$template" "$deploy_template"
  echo "" >>"$deploy_template"
  local temp_file_0 && temp_file_1="$(mktemp)"
  cat "$deploy_template" "$temp_file_0" >"$temp_file_1"
  cp "$temp_file_1" "$deploy_template"
  rm "$temp_file_1" "$temp_file_0"
}

deploy_stack() {
  create_deploy_template
  local deploy_command="aws cloudformation deploy --template-file $deploy_template  --stack-name $stack_name --capabilities CAPABILITY_IAM $default_aws_arguments"
  if $dry_run; then
    deploy_command+=' --no-execute-changeset'
  fi

  local deploy_output && deploy_output=$(eval "$deploy_command")
  rm "$deploy_template"
  local label='aws cloudformation deploy'
  if $dry_run; then
    label="[dry run] $label"
  fi
  echo "$deploy_output" | bat --file-name="$label" --pager=none
  local ultimate_line && ultimate_line=$(echo "$deploy_output" | tail -n1)
  local regex='^aws cloudformation describe-change-set'
  if [[ ! "$ultimate_line" =~ $regex ]]; then
    return
  fi

  if $dry_run; then
    local describe_command="$ultimate_line $default_aws_arguments"
    local describe_output && describe_output=$(eval "$describe_command")
    label='aws cloudformation describe-change-set'
    if $dry_run; then
      label="[dry run] $label"
    fi
    echo "$describe_output" | bat --file-name="$label" --pager=none --language=json
    return
  fi

  set_config
}

get_lambda_bucket_name() {
  if [ '' == "$json_config" ]; then
    if [ -f "$config_file" ]; then
      json_config=$(jq <"$config_file")
    else
      set_config
    fi
  fi
  echo "$json_config" | jq -r '.LambdaFunctionBucketRef'
}

upload_lambda_functions() {
  local tempdir && tempdir="$(mktemp -d)"
  local tempvar
  while IFS= read -r filepath; do
    tempvar=$(dirname "$(realpath "$filepath")")
    version=${tempvar##*/}
    tempvar=$(dirname "$(dirname "$(realpath "$filepath")")")
    function_name=${tempvar##*/}
    dir="$tempdir/$function_name/$version"
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir"
    fi
    cp "$filepath" "$dir/index.js"
    zip -r -j -X -q "$dir/index.js.zip" "$dir"
    rm "$dir/index.js"
  done < <(find "$here/lambda-functions/." -name '*.js')

  local latest
  for function in "$tempdir"/*; do
    for version in "$function"/*; do
      latest="$version"
    done
    cp -r "$latest" "$function/latest"
  done

  local lambda_bucket && lambda_bucket=$(get_lambda_bucket_name)
  local cmd && cmd="aws s3 sync $tempdir s3://$lambda_bucket --delete --size-only --profile personal"
  if $dry_run; then
    cmd+=' --dryrun'
  fi

  local sync_output && sync_output=$(eval "$cmd")
  local label='aws s3 sync'
  if $dry_run; then
    label="[dry run] $label"
  fi
  echo "$sync_output" | bat --file-name="$label" --pager=none

  rm -rf "$tempdir"
}

set_config() {
  local outputs && outputs=$(eval "aws cloudformation describe-stacks $default_aws_arguments \
    --stack-name $stack_name \
    --query \"Stacks[0].Outputs\"")

  json_config='{'
  while read -r OutputKey; do
    read -r OutputValue
    json_config+="\"$OutputKey\":\"$OutputValue\","
  done < <(echo "$outputs" | jq -cr '.[] | (.OutputKey, .OutputValue)')
  json_config=${json_config%?}
  json_config+='}'

  echo "$json_config" >"$config_file"
}

main() {
  if ! [ -x "$(command -v jq)" ]; then
    echo 'exiting early: jq not installed'
    exit
  fi

  if ! [ -x "$(command -v yq)" ]; then
    echo 'exiting early: yq not installed'
    exit
  fi

  deploy_stack
  upload_lambda_functions
}

main
