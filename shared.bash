#! /usr/bin/env bash
set -e

if ! [ -x "$(command -v jq)" ]; then
  echo 'exiting early: jq not installed'
  exit
fi

if ! [ -x "$(command -v yq)" ]; then
  echo 'exiting early: yq not installed'
  exit
fi

if [ -z "$1" ]; then
  readonly stack='abr'
fi

json_config=
region='us-east-1'
stack_name="$stack-$region"
[ -z "$profile" ] && profile='personal'
default_aws_arguments="--region $region --profile $profile"

if [ '' == "$account_id" ]; then
  account_id=$(aws sts get-caller-identity --profile "$profile" | jq -r '.Account')
fi

set_config() {
  # todo: get this directly from the resources of the stack, not the outputs
  local describe_stacks_outputs && describe_stacks_outputs=$(eval "aws cloudformation describe-stacks $default_aws_arguments \
    --stack-name $stack_name \
    --query \"Stacks[0].Outputs\"")

  json_config='{'
  while read -r OutputKey; do
    read -r OutputValue
    json_config+="\"$OutputKey\":\"$OutputValue\","
  done < <(echo "$describe_stacks_outputs" | jq -cr '.[] | (.OutputKey, .OutputValue)')
  json_config=${json_config%?}
  json_config+='}'
}

init_config() {
  if [ '' == "$json_config" ]; then
    set_config
  fi
}

get_bucket_name() {
  local name="$1"
  init_config
  local bucket_name && bucket_name=$(echo "$json_config" | jq -r ".${name}BucketRef")
  if [ '' == "$bucket_name" ]; then
    echo "$account_id-$stack_name-$(pascal_to_kabob "$name")"
  else
    echo "$bucket_name"
  fi
}

get_distribution_id() {
  local name="$1"
  init_config
  local id && id=$(echo "$json_config" | jq -r ".${name}DistributionId")
  if [ 'null' == "$id" ]; then
    echo ''
    return
  fi
  echo "$id"
}

get_distribution_alias() {
  local name="$1"
  local id && id="$(get_distribution_id "$name")"
  local distribution_config && distribution_config=$(aws cloudfront get-distribution-config --id "$id" --profile "$profile")
  local alias && alias=$(jq -r '.DistributionConfig.Aliases.Items[0]' <<<"$distribution_config")
  if [ 'null' == "$alias" ]; then
    echo ''
    return
  fi
  echo "$alias"
}

get_distribution_domain_name() {
  local name="$1"
  init_config
  local id && id=$(echo "$json_config" | jq -r ".${name}DistributionDomainName")
  if [ 'null' == "$id" ]; then
    echo ''
    return
  fi
  echo "$id"
}

get_function_arn() {
  local name="$1"
  init_config
  local arn && arn=$(echo "$json_config" | jq -r ".${name}Arn")
  if [ 'null' == "$arn" ]; then
    echo ''
  else
    echo "$arn"
  fi
}

capitalize() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

kabob_to_snake() {
  local kabob="$1"
  local snake="${kabob//-/_}"
  echo "$snake"
}

snake_to_kabob() {
  local snake="$1"
  local kabob="${snake//_/-}"
  echo "$kabob"
}

snake_to_pascal() {
  local snake="$1"
  local pascal=''
  IFS='_' read -ra words <<<"$snake"
  for word in "${words[@]}"; do
    first_char=${word:0:1}
    first_char_capitalized=$(capitalize "$first_char")
    pascal+=$(echo "$word" | sed "s/^$first_char/$first_char_capitalized/g")
  done
  echo "$pascal"
}

snake_to_camel() {
  local snake="$1"
  local pascal && pascal=$(snake_to_pascal "$snake")
  local first_char=${pascal:0:1}
  local first_char_lowercased && first_char_lowercased=$(lowercase "$first_char")
  echo "$pascal" | sed "s/^$first_char/$first_char_lowercased/g"
}

kabob_to_pascal() {
  local kabob="$1"
  local snake && snake=$(kabob_to_snake "$kabob")
  echo "$(snake_to_pascal "$snake")"
}

pascal_to_kabob() {
  local pascal="$1"
  echo "$pascal" | sed -r 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]'
}
