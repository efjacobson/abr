#! /bin/bash

attempts=0
readonly max_attempts=1
# (us(-gov)?|af|ap|ca|eu|me|sa)-(north|east|south|west|central)+-\d+
last_good_parameter_overrides=()
default_aws_arguments=
region=
profile=
dry_run=false # todo: danger, sort of. looks like its gonna get stuck in a loop

stack='abr'
stack_name=
account_id=

here="$(dirname "$(realpath "$0")")"
readonly here
readonly template="$here/infra.yaml"
readonly drift_path="$here/.$stack-drift"
readonly create_path="$here/.$stack-create"
readonly head_object_path="$here/.$stack-head-object"
readonly get_function_path="$here/.$stack-get-function"

display_help() {
  echo "
Available options:
  --dry-run     When true, no changes are actually made
  --stack       Defaults to '$stack'
  --account-id  Your AWS account id
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
  --stack=*)
    stack="${opt#*=}"
    ;;
  --account-id=*)
    account_id="${opt#*=}"
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
  local AWSCloudFrontCloudFrontOriginAccessIdentity_output_GetAtt_fields=('Id' 'S3CanonicalUserId')
  local AWSCloudFrontDistribution_output_GetAtt_fields=('DomainName' 'Id')
  local AWSIAMRole_output_GetAtt_fields=('Arn' 'RoleId')
  local AWSLambdaFunction_output_GetAtt_fields=('Arn')
  local AWSLambdaVersion_output_GetAtt_fields=('Version')
  local AWSLogsLogGroup_output_GetAtt_fields=('Arn')
  local AWSS3Bucket_output_GetAtt_fields=('Arn' 'DomainName' 'DualStackDomainName' 'RegionalDomainName' 'WebsiteURL')
  local AWSServerlessFunction_output_GetAtt_fields=('Arn')
  local AWSCloudFrontOriginAccessControl_output_GetAtt_fields=('Id')

  local temp_file_0 && temp_file_0="$(mktemp)"
  echo '{}' >"$temp_file_0"
  local outputs && outputs=$(echo '{}' | jq)
  yq '.Resources | keys[]' "$template" | while read -r resource; do
    local raw_resource && raw_resource=$(echo "$resource" | tr -d '"')
    local Ref_filter=". + {\"${raw_resource}Ref\": {\"Value\": \"!Ref $raw_resource\""
    local condition && condition="$(yq ".Resources.$raw_resource.Condition" "$template")"
    if [ 'null' != "$condition" ]; then
      Ref_filter+=",\"Condition\":$condition"
    fi
    Ref_filter+='}}'
    outputs=$(echo "$outputs" | jq "$Ref_filter")

    local filter=".Resources.$raw_resource.Type"
    local type && type=$(yq -r "$filter" "$template")
    local config=${type//:/}
    local output_fields="$config"_output_GetAtt_fields[@]
    local count=0
    for GetAtt_field in ${!output_fields}; do
      GetAtt_filter=". + {\"$raw_resource$GetAtt_field\": {\"Value\": \"!GetAtt $raw_resource.$GetAtt_field\""
      if [ 'null' != "$condition" ]; then
        GetAtt_filter+=",\"Condition\":$condition"
      fi
      GetAtt_filter+='}}'
      outputs=$(echo "$outputs" | jq "$GetAtt_filter")
      count=$((count + 1))
    done
    if [ "$count" == 0 ] && [ 'AWSS3BucketPolicy' != "$config" ] && [ 'AWSLambdaPermission' != "$config" ]; then
      echo "no config for $config!"
    fi
    local insert_filter=". + {\"Outputs\":$outputs}"
    local result && result=$(cat "$temp_file_0" | yq "$insert_filter")
    echo "$result" >"$temp_file_0"
  done
  local final_outputs && final_outputs=$(cat "$temp_file_0" | yq -y | sed -E 's/(Value: '\'')/Value: /g' | sed -E 's/^(.+)Value(.+)('\'')$/\1Value\2/g')
  echo "$final_outputs" >"$temp_file_0"
  local deploy_template && deploy_template=$(mktemp)
  cp "$template" "$deploy_template"
  echo "" >>"$deploy_template"
  local temp_file_0 && temp_file_1="$(mktemp)"
  cat "$deploy_template" "$temp_file_0" >"$temp_file_1"
  cp "$temp_file_1" "$deploy_template"
  rm "$temp_file_1" "$temp_file_0"
  echo "$deploy_template"
}

deploy_stack() {
  echo 'wrong'
  exit
  local parameter_overrides=("$@")
  local deploy_template && deploy_template=$(create_deploy_template "${parameter_overrides[@]}")

  parameter_overrides+=("DefaultBucketOnCreateObjectFunctionArn=$(get_function_arn 'DefaultBucketOnCreateObjectFunction')")
  parameter_overrides+=('IsCreate=false')
  parameter_overrides_option="--parameter-overrides ${parameter_overrides[*]}"

  for override in "${parameter_overrides[@]}"; do
    echo "about to deploy with override: $override"
  done
  exit
  local deploy_command="aws cloudformation deploy \
    --template-file $deploy_template  \
    --stack-name $stack_name \
    --capabilities CAPABILITY_IAM \
    $parameter_overrides_option \
    $default_aws_arguments"

  echo 'deploying...'
  local deploy_output && deploy_output=$(eval "$deploy_command")
  rm "$deploy_template"
  local label="$deploy_command"
  if $dry_run; then
    label="[dry run] $label"
  fi
  echo "$deploy_output"

  local ultimate_line && ultimate_line=$(echo "$deploy_output" | tail -n1)

  if [[ ! "$ultimate_line" =~ ^aws\scloudformation\sdescribe-change-set ]]; then
    return
  fi
  last_good_parameter_overrides=parameter_overrides
  set_config

  # if $dry_run; then
  #   local describe_command="$ultimate_line $default_aws_arguments"
  #   local describe_output && describe_output=$(eval "$describe_command")
  #   label=describe_command
  #   if $dry_run; then
  #     label="[dry run] $label"
  #   fi
  #   echo "$describe_output"
  #   return
  # fi

  # set_config
}

deploy_stack_new() {
  local parameters=$1

  on_create_arn=$(get_function_arn 'DefaultBucketOnCreateObjectFunction')
  if [ -n "$on_create_arn" ]; then
    parameters=$(jq --arg arn "$on_create_arn" '.DefaultBucketOnCreateObjectFunctionArn = $arn' <<<"$parameters")
  fi
  parameters=$(jq '.IsCreate = false' <<<"$parameters")

  echo "$(for_update "$parameters")"

  local -r deploy_response=$(eval "aws cloudformation deploy \
    --region $region \
    --profile $profile \
    --stack-name $stack_name \
    --capabilities CAPABILITY_IAM \
    --template-file $(create_deploy_template) \
    --parameter-overrides $(for_update "$parameters")" 2>&1 | sed '/^$/d')

  # aws cloudformation deploy \
  #   --region "$region" \
  #   --profile "$profile" \
  #   --stack-name "$stack_name" \
  #   --capabilities CAPABILITY_IAM \
  #   --template-file "$(create_deploy_template)" \
  #   --parameter-overrides "$(for_update "$parameters")" | jq

  set_config
  echo "$deploy_response"
}

get_latest_version() {
  local function="$1"
  local latest
  for version in "$here/lambda-functions/$function"/*; do
    latest=${version##*/}
  done
  if [ '*' == "$latest" ]; then
    echo "no versions for function: $function. exiting early..."
    exit
  fi
  echo "$latest"
}

create_stack() {
  echo 'creating stack...'
  eval "aws cloudformation create-stack \
    --stack-name $stack_name \
    --template-body file://$(create_deploy_template) \
    --region $region \
    --profile $profile \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection \
    --parameters $(for_create "$1")" | jq

  local describe_response
  local status
  local flag=true # simulate do-while loop
  while $flag || [ 'CREATE_IN_PROGRESS' == "$status" ]; do
    if ! $flag; then
      echo 'sleeping for 60 seconds...'
      sleep 60
    fi
    flag=false
    describe_response=$(aws cloudformation describe-stacks --stack-name="$stack_name" --profile "$profile" --region="$region" 2>&1 | sed '/^$/d')
    status=$(jq -r '.Stacks[0].StackStatus' <<<"$describe_response")
  done
  if [ 'CREATE_COMPLETE' != "$status" ]; then
    jq <<<"$describe_response"
    echo 'something went wrong ^^'
    exit
  fi
  echo 'stack creation complete...'
  return 0
}

upload_lambda_functions() {
  for function in "$here/lambda-functions"/*; do
    if [ -d "$function/latest" ]; then
      rm -rf "$function/latest"
    fi
  done

  local -r bucket="$(get_bucket_name 'LambdaFunction')"
  local head_object_response
  while IFS= read -r filepath; do
    base_name="$(basename "$filepath")"
    dir_name="$(dirname "$(realpath "$filepath")")"
    dir_names_dir_name=$(dirname "$dir_name")

    function_name=${dir_names_dir_name##*/}
    version=${dir_name##*/}
    key="$function_name/$version/$base_name.zip"

    zip_path="$filepath.zip"
    zip -j -X -q "$zip_path" "$filepath"
    checksum="$(openssl dgst -sha256 -binary "$zip_path" | openssl enc -base64)"

    aws s3api head-object --bucket "$bucket" --key "$key" --checksum-mode ENABLED --profile "$profile" >"$head_object_path" 2>&1
    sed -i '/^$/d' "$head_object_path"
    head_object_response=$(cat "$head_object_path")
    if [ 'An error occurred (404) when calling the HeadObject operation: Not Found' == "$head_object_response" ]; then
      aws s3api put-object \
        --bucket "$bucket" \
        --key "$key" \
        --body "$zip_path" \
        --checksum-sha256 "$checksum" \
        --profile "$profile" >>/dev/null
      echo "uploaded $key to s3://$bucket/$key with sha256 checksum $checksum"
      rm -f "$zip_path"
    elif [ "$checksum" == "$(jq -r '.ChecksumSHA256' "$head_object_path")" ]; then
      rm -f "$zip_path"
      continue
    else
      echo "$head_object_response"
      echo "local/s3 checksums do not match for $key, check the response above"
      exit
    fi
  done < <(find "$here/lambda-functions/." -name '*.js')

  for function in "$here/lambda-functions"/*; do
    cp -r "$function/$(get_latest_version "${function##*/}")" "$function/latest"
  done
}

for_create() {
  local parameters=''
  while read -r entry; do
    parameters+="ParameterKey=$(jq -r '.key' <<<"$entry"),ParameterValue=$(jq -r '.value' <<<"$entry") "
  done < <(jq -c 'to_entries[]' <<<"$1")
  echo "$parameters"
}

for_update() {
  local overrides=''
  while read -r key; do
    value=$(jq -r --arg k "$key" '."\($k)"' <<<"$1")
    overrides+="$key=$value "
  done < <(jq -r 'keys[]' <<<"$1")
  echo "$overrides"
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

  # shellcheck source=/dev/null
  source "$here/shared.bash" "$stack"

  attempts=$((attempts + 1))
  if [ $attempts -gt $max_attempts ]; then
    for path in $drift_path $create_path $head_object_path; do
      if [ -f "$path" ]; then
        rm -f "$path"
      fi
    done
    echo "exceeded $max_attempts attempts, bailing out..."
    exit
  fi
  echo "attempts: $attempts"

  local -r latest_on_create='default-bucket-on-create-object'
  local -r latest_on_origin='default-bucket-on-origin-request'
  local -r latest_on_create_version=$(get_latest_version "$latest_on_create")
  local -r latest_on_origin_version=$(get_latest_version "$latest_on_origin")
  local -r latest_on_origin_version_friendly="${latest_on_origin_version//./-}"

  local parameters
  parameters='{'
  parameters+='"IsCreate":true'
  parameters+=','
  parameters+="\"DefaultBucketOnCreateObjectFunctionSemanticVersion\":\"$(get_latest_version 'default-bucket-on-create-object')\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromFileName\":\"$stack_name-OnOriginRequest_$latest_on_origin_version_friendly-file\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromAssociationName\":\"$stack_name-OnOriginRequest_$latest_on_origin_version_friendly-association\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion\":\"$latest_on_origin_version\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion\":\"$latest_on_origin_version\""
  parameters+='}'

  local -r describe_response=$(aws cloudformation describe-stacks \
    --stack-name="$stack_name" \
    --profile "$profile" \
    --region="$region" 2>&1 | sed '/^$/d')
  if [ "$describe_response" == "An error occurred (ValidationError) when calling the DescribeStacks operation: Stack with id $stack_name does not exist" ]; then
    if ! create_stack "$parameters"; then
      exit
    fi
  else
    local -r detection_id=$(eval "aws cloudformation detect-stack-drift \
      --stack-name $stack_name \
      --output=text \
      --profile $profile \
      --region $region")

    local detect_response
    local detection_status
    local flag=true # simulate do-while loop
    while $flag || [ 'DETECTION_IN_PROGRESS' == "$detection_status" ]; do
      if ! $flag; then
        echo 'drift being detected, sleeping for 5 seconds...'
        sleep 5
      fi
      flag=false
      detect_response=$(aws cloudformation describe-stack-drift-detection-status \
        --stack-drift-detection-id "$detection_id" \
        --profile "$profile" \
        --region "$region" 2>&1)
      detection_status="$(jq -r '.DetectionStatus' <<<"$detect_response")"
    done
    if [ 'DETECTION_COMPLETE' != "$detection_status" ]; then
      jq <<<"$detect_response"
      echo 'something went wrong ^^'
      exit
    fi

    drift_status="$(jq -r '.StackDriftStatus' <<<"$detect_response")"
    if [ 'IN_SYNC' != "$drift_status" ]; then
      while true; do
        read -r -p "stack is not in sync, has status [$drift_status]. continue deploying? (y/N): " answer
        case "$answer" in
        Y | y)
          break
          ;;
        *)
          exit
          ;;
        esac
      done
    else
      echo 'stack is in sync...'
    fi
  fi

  local parameter_overrides=()

  # local need_to_upload=false
  local -r keys=(
    "$(snake_to_kabob "$latest_on_origin")/$latest_on_origin_version/index.js.zip"
    "$(snake_to_kabob "$latest_on_create")/$latest_on_create_version/index.js.zip"
  )
  for key in "${keys[@]}"; do
    head_object_response=$(aws s3api head-object --bucket "$account_id-$stack_name-lambda-function" --key "$key" --profile "$profile" 2>&1 | sed '/^$/d')
    if [ "$head_object_response" == 'An error occurred (404) when calling the HeadObject operation: Not Found' ]; then
      upload_lambda_functions
      break
    fi
  done
  echo 'latest lambdas are in the bucket...'

  local distribution_id
  distribution_id=$(get_distribution_id 'Primary')
  readonly distribution_id

  local -r long_name=$(kabob_to_pascal "$latest_on_origin")
  local -r short_name="${long_name/DefaultBucket/}"

  if [ -z "$distribution_id" ]; then
    deploy_stack_response=$(deploy_stack_new $parameters)
    if [ "$(echo "$deploy_stack_response" | tail -n1)" != "Successfully created/updated stack - $stack_name" ]; then
      echo "$deploy_stack_response"
      echo 'something went wrong ^^'
      exit
    fi
  fi

  local -r associations=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile "$profile" --query="DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations")
  if [ '0' == "$(echo "$associations" | jq '.Quantity')" ]; then
    echo 'no associations found...'
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileName=$stack_name-${short_name}_$latest_on_origin_version_friendly-file")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion=$latest_on_origin_version")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationName=$stack_name-${short_name}_$latest_on_origin_version_friendly-association")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion=$latest_on_origin_version")
    echo 'here 2'
    deploy_stack "${parameter_overrides[@]}"
    echo 'should deploy again here 2?'
    exit
  fi

  echo 'associations found...'

  origin_request_lambda_association=$(echo "$associations" | jq '.Items[] | select(.EventType=="origin-request")')
  if [ '' == "$origin_request_lambda_association" ]; then
    echo 'no origin-request associations found...'
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileName=$stack_name-${short_name}_$latest_on_origin_version_friendly-file")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion=$latest_on_origin_version")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationName=$stack_name-${short_name}_$latest_on_origin_version_friendly-association")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion=$latest_on_origin_version")
    echo 'here 3'
    deploy_stack "${parameter_overrides[@]}"
    echo 'should deploy again here? 3'
    exit
  fi

  # [v2,v1]
  # INVALID - v1-0 not ready to be deleted yet, refuse to deploy

  origin_request_lambda_function_arn=$(echo "$origin_request_lambda_association" | jq -r '.LambdaFunctionARN')
  version="${origin_request_lambda_function_arn##*_}"
  version=$(echo "$version" | sed -E 's/:[0-9]+$//')
  version="${version//-/.}"
  version=$(echo "$version" | sed 's/\.\(file\|association\)$//')
  # version="${version//.association/}"
  # version="${version//.file/}"
  SemanticVersionFromDistro="$version"
  echo "SemanticVersionFromDistro $SemanticVersionFromDistro"
  if [ "$SemanticVersionFromDistro" == "$latest_on_origin_version" ]; then
    echo 'latest and associated are equal...'
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileName=$stack_name-${short_name}_$latest_on_origin_version_friendly-file")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion=$latest_on_origin_version")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationName=$stack_name-${short_name}_$latest_on_origin_version_friendly-association")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion=$latest_on_origin_version")
    parameter_overrides+=('ShouldUseFunctionFromAssociation=true')
    echo 'set ShouldUseFunctionFromAssociation to true'
    deploy_stack "${parameter_overrides[@]}"
    # echo 'nothing association related to do but ofc still need to deploy for normals stuff'
    exit
  fi

  high_version=$(highest_version "$SemanticVersionFromDistro" "$latest_on_origin_version")
  if [ "$high_version" == "$SemanticVersionFromDistro" ]; then
    echo "distro is associated with version '$SemanticVersionFromDistro', local version is '$latest_on_origin_version'. refusing to update distro with lower version..."
    exit
  fi

  eval "aws lambda get-function --function-name $stack_name-${short_name}_$latest_on_origin_version_friendly-file --region $region --profile $profile" >"$get_function_path" 2>&1
  get_function_response="$(cat "$get_function_path")"
  if [[ "$get_function_response" =~ .*ResourceNotFoundException.* ]]; then
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileName=$stack_name-${short_name}_$latest_on_origin_version_friendly-file")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion=$latest_on_origin_version")

    prefix="arn:aws:lambda:$region:$account_id:function:"
    associated_lambda_name=${origin_request_lambda_function_arn/$prefix/}
    associated_lambda_name=$(echo "$associated_lambda_name" | sed 's/:[[:digit:]]\+//')
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationName=$associated_lambda_name")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion=$SemanticVersionFromDistro")
    deploy_stack "${parameter_overrides[@]}"
    echo 'should deploy again here? 5'
    echo 'after checking for errors, should deploy again immediately? do you really need to go through the whole flow again to get into the else for this if?'
  else # todo: check for success properly here and in many other places
    echo 'function already exists'
    echo "get_function_response: $get_function_response"
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationName=$stack_name-${short_name}_$latest_on_origin_version_friendly-association")
    parameter_overrides+=("DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion=$latest_on_origin_version")
    parameter_overrides+=('ShouldUseFunctionFromAssociation=false')
    deploy_stack "${parameter_overrides[@]}"
    echo 'should deploy again here? 6'
    echo 'assuming things went well...'
  fi
  rm -f "$get_function_path"
  exit

  # if latest is higher version than associated for ex v2 and v1
  # deploy with latest v2, associated v1

  # then deploy and swap so that the distribution associates the one "from the file"

  # then deploy with both v2

  # improvements: naming, only having 2 when needed
}

highest_version() {
  local -r version_a="$1"
  local -r version_b="$2"
  if [ "$version_a" == "$version_b" ]; then
    echo "versions are the same, chucklehead..." >&2
    exit
  fi

  local a=${version_a/v/}
  a=${a//./ }
  read -r -a version_a_as_array <<<"$a"

  local b=${version_b/v/}
  b=${b//./ }
  read -r -a version_b_as_array <<<"$b"

  local highest
  local length="${#version_a_as_array[@]}"
  for ((i = 0; i <= length; i++)); do
    if [ "${version_a_as_array[$i]}" -eq "${version_b_as_array[$i]}" ]; then
      continue
    elif [ "${version_a_as_array[$i]}" -gt "${version_b_as_array[$i]}" ]; then
      highest="$version_a"
      break
    else
      highest="$version_b"
      break
    fi
  done
  echo "$highest"
}

main
