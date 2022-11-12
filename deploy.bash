#! /bin/bash

template='./infra.yaml'
deploy_template='./infra.deploy.yaml'
json_config=
region='us-east-1'
stack_name='abr'

config_file="./.$stack_name-stack-outputs.json"
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

  local tmp_file='infra.tmp.json'
  if [ -d "$tmp_file" ]; then
    rm "$tmp_file"
  fi
  echo '{}' >"$tmp_file"
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
    local result && result=$(cat "$tmp_file" | yq "$insert_filter")
    echo "$result" >"$tmp_file"
  done
  local final_outputs && final_outputs=$(cat "$tmp_file" | yq -y | sed -E 's/(Value: '\'')/Value: /g' | sed -E 's/^(.+)Value(.+)('\'')$/\1Value\2/g')
  echo "$final_outputs" >"$tmp_file"
  cp "$template" "$deploy_template"
  echo "" >>"$deploy_template"
  cat "$deploy_template" "$tmp_file" >'even-more-tmp-file'
  cp 'even-more-tmp-file' "$deploy_template"
  rm 'even-more-tmp-file' "$tmp_file"
}

deploy_stack() {
  create_deploy_template
  local deploy_command="aws cloudformation deploy --template-file $deploy_template  --stack-name $stack_name $default_aws_arguments"
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
  if [ "No changes to deploy. Stack $stack_name is up to date" == "$ultimate_line" ]; then
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
    if [ -f $config_file ]; then
      json_config=$(jq <$config_file)
    else
      set_config
    fi
  fi
  echo "$json_config" | jq -r '.LambdaFunctionBucketRef'
}

upload_lambda_functions() {
  local workdir && workdir="$(mktemp -d)"
  local dir
  for filepath in ./functions/*/*; do
    file=$(basename "$filepath")
    dir=$(dirname "$(realpath "$filepath")")
    version=${dir##*/}
    if [ ! -d "$workdir/$version" ]; then
      mkdir "$workdir/$version"
    fi
    zip -j -X -q "$workdir/$version/$file.zip" "$filepath"
  done

  local lambda_bucket && lambda_bucket=$(get_lambda_bucket_name)
  local cmd && cmd="aws s3 sync $workdir s3://$lambda_bucket --delete --profile personal"
  if $dry_run; then
    cmd+=' --dryrun'
  fi

  local sync_output && sync_output=$(eval "$cmd")
  local label='aws s3 sync'
  if $dry_run; then
    label="[dry run] $label"
  fi
  echo "$sync_output" | bat --file-name="$label" --pager=none

  rm -rf "$workdir"
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

  echo "$json_config" >$config_file
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
