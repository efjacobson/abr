#! /bin/bash

# (us(-gov)?|af|ap|ca|eu|me|sa)-(north|east|south|west|central)+-\d+
region=
profile=
dry_run=false # todo: danger, sort of. looks like its gonna get stuck in a loop

stack='abr'
stack_name=
account_id=

here="$(dirname "$(realpath "$0")")"
readonly here
readonly template="$here/infra.yaml"

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
  # todo: only need to do this once per script execution, also want to make sure to immediately dupe the original template to prevent unintentional wackiness
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
  local parameters=$1

  on_create_arn=$(get_function_arn 'DefaultBucketOnCreateObjectFunction')
  if [ -n "$on_create_arn" ]; then
    parameters=$(jq --arg arn "$on_create_arn" '.DefaultBucketOnCreateObjectFunctionArn = $arn' <<<"$parameters")
  fi
  parameters=$(jq '.IsFirstRun = false' <<<"$parameters")

  local -r deploy_response=$(eval "aws cloudformation deploy \
    --region $region \
    --profile $profile \
    --stack-name $stack_name \
    --capabilities CAPABILITY_IAM \
    --template-file $(create_deploy_template) \
    --parameter-overrides $(for_update "$parameters")" 2>&1 | sed '/^$/d')
  echo "$deploy_response"

  if [ "Successfully created/updated stack - $stack_name" == "$(tail -n1 <<<"$deploy_response")" ]; then
    set_config
  elif [ "No changes to deploy. Stack $stack_name is up to date" != "$(tail -n1 <<<"$deploy_response")" ]; then
    echo 'something went wrong ^^'
    exit
  fi
  return 0
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
  local sleep=30
  while $flag || [ 'CREATE_IN_PROGRESS' == "$status" ]; do
    if ! $flag; then
      echo "sleeping for $sleep seconds..."
      sleep $sleep
      sleep=$((sleep / 2))
      if [ $sleep -lt 5 ]; then
        sleep=10
      fi
    fi
    flag=false
    describe_response=$(aws cloudformation describe-stacks --stack-name="$stack_name" --profile "$profile" --region="$region" 2>&1 | sed '/^$/d')
    status=$(jq -r '.Stacks[0].StackStatus' <<<"$describe_response")
  done
  echo "$describe_response"
  if [ 'CREATE_COMPLETE' != "$status" ]; then
    echo 'something went wrong ^^'
    exit
  fi
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

    head_object_response=$(eval "aws s3api head-object \
      --bucket $bucket \
      --key $key \
      --checksum-mode ENABLED \
      --profile $profile" 2>&1 | sed '/^$/d')
    if [ 'An error occurred (404) when calling the HeadObject operation: Not Found' == "$head_object_response" ]; then
      aws s3api put-object \
        --bucket "$bucket" \
        --key "$key" \
        --body "$zip_path" \
        --checksum-sha256 "$checksum" \
        --profile "$profile" >>/dev/null
      echo "uploaded $key to s3://$bucket/$key with sha256 checksum $checksum"
      rm -f "$zip_path"
    elif [ "$checksum" == "$(jq -r '.ChecksumSHA256' <<<"$head_object_response")" ]; then
      rm -f "$zip_path"
      continue
    else
      rm -f "$zip_path"
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

main() {
  local -r latest_on_origin='default-bucket-on-origin-request'
  local -r latest_on_origin_version=$(get_latest_version "$latest_on_origin")
  local -r latest_on_origin_version_friendly="${latest_on_origin_version//./-}"
  local -r latest_on_origin_prefix="$stack_name-OnOriginRequest_$latest_on_origin_version_friendly"

  local parameters
  parameters='{'
  parameters+='"IsFirstRun":true'
  parameters+=','
  parameters+="\"DefaultBucketOnCreateObjectFunctionSemanticVersion\":\"$(get_latest_version 'default-bucket-on-create-object')\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromFileName\":\"$latest_on_origin_prefix-file\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromAssociationName\":\"$latest_on_origin_prefix-association\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion\":\"$latest_on_origin_version\""
  parameters+=','
  parameters+="\"DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion\":\"$latest_on_origin_version\""
  parameters+='}'

  local -r describe_response=$(aws cloudformation describe-stacks \
    --stack-name="$stack_name" \
    --profile "$profile" \
    --region="$region" 2>&1 | sed '/^$/d')
  local -r status="$(jq -r '.Stacks[0].StackStatus' <<<"$describe_response")"
  if [ "$describe_response" == "An error occurred (ValidationError) when calling the DescribeStacks operation: Stack with id $stack_name does not exist" ]; then
    if ! create_stack "$parameters"; then
      exit
    fi
  elif [ 'ROLLBACK_COMPLETE' == "$status" ]; then
    local -r list_resources_response=$(aws cloudformation describe-stack-resources \
      --stack-name="$stack_name" \
      --profile "$profile" \
      --region="$region" 2>&1 | sed '/^$/d')
    local -r completed_resources=$(jq -r '.StackResources[] | select(.ResourceStatus|test("^(?!DELETE).+"))' <<<"$list_resources_response")
    if [ -z "$completed_resources" ]; then
      echo 'first run failed, deleting...'
      "$here"/delete-stack.bash --stack="$stack"
      echo 'creating new stack'
      if ! create_stack "$parameters"; then
        exit
      fi
    else
      echo "drift cannot be detected because stack is in state '$status'. ride or die..."
    fi
  else
    local -r detection_id=$(eval "aws cloudformation detect-stack-drift \
      --stack-name $stack_name \
      --output=text \
      --profile $profile \
      --region $region" 2>&1 | sed '/^$/d')

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
      echo "$detect_response"
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
    fi
  fi

  local -r lambda_bucket="$account_id-$stack_name-lambda-function"
  local -r latest_on_create='default-bucket-on-create-object'
  local -r keys=(
    "$(snake_to_kabob "$latest_on_origin")/$latest_on_origin_version/index.js.zip"
    "$latest_on_create/$(get_latest_version "$latest_on_create")/index.js.zip"
  )
  for key in "${keys[@]}"; do
    head_object_response=$(aws s3api head-object --bucket "$lambda_bucket" --key "$key" --profile "$profile" 2>&1 | sed '/^$/d')
    if [ "$head_object_response" == 'An error occurred (404) when calling the HeadObject operation: Not Found' ]; then
      upload_lambda_functions
      break
    fi
  done

  local distribution_id
  distribution_id=$(get_distribution_id 'Primary')

  if [ -z "$distribution_id" ]; then
    echo 'deploying to create distribution'
    if ! deploy_stack "$parameters"; then
      exit
    fi
    distribution_id=$(get_distribution_id 'Primary')
    if [ -z "$distribution_id" ]; then
      echo 'the primary distribution should exist by now, but it doesn'\''t. exiting early...'
      exit
    fi
  fi
  parameters=$(jq '.PrimaryDistributionExists = true' <<<"$parameters")

  local associations && associations=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile "$profile" --query="DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations")

  if [[ ! "$(jq '.Quantity' <<<"$associations")" =~ ^[1-9][0-9]*$ ]]; then
    echo 'deploying because there are no associations'
    if ! deploy_stack "$parameters"; then
      exit
    fi
  fi

  origin_request_lambda_association=$(jq '.Items[] | select(.EventType=="origin-request")' <<<"$associations")
  if [ -z "$origin_request_lambda_association" ]; then
    echo 'deploying because there is no origin request association'
    if ! deploy_stack "$parameters"; then
      exit
    fi
    associations=$(aws cloudfront get-distribution-config --id "$distribution_id" --profile "$profile" --query="DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations")
    origin_request_lambda_association=$(jq '.Items[] | select(.EventType=="origin-request")' <<<"$associations")
    if [ -z "$origin_request_lambda_association" ]; then
      echo 'there should be an origin request lambda by now but there isn'\''t. exiting early...'
      exit
    fi
  fi

  origin_request_lambda_association_arn=$(jq -r '.LambdaFunctionARN' <<<"$origin_request_lambda_association")
  distro_version="${origin_request_lambda_association_arn##*_}"
  distro_version="${distro_version%:*}"
  distro_version="${distro_version//-/.}"
  distro_version="${distro_version/.file/}"
  distro_version="${distro_version/.association/}"
  if [ "$distro_version" == "$latest_on_origin_version" ]; then
    echo 'deploying because this command should always deploy at least once'
    parameters=$(jq '.ShouldUseFunctionFromAssociation = true' <<<"$parameters")
    if deploy_stack "$parameters"; then
      echo 'done.'
    fi
    exit
  fi

  if [ "$distro_version" == "$(highest_version "$distro_version" "$latest_on_origin_version")" ]; then
    echo "distro is associated with version '$distro_version', local version is '$latest_on_origin_version'. refusing to update stack with lower version..."
    exit
  fi

  local -r get_function_response=$(eval "aws lambda get-function \
    --function-name $latest_on_origin_prefix-file \
    --region $region \
    --profile $profile" 2>&1 | sed '/^$/d')

  if [[ "$get_function_response" =~ .*ResourceNotFoundException.* ]]; then
    local associated_lambda_name=${origin_request_lambda_association_arn/arn:aws:lambda:$region:$account_id:function:/}
    associated_lambda_name="${associated_lambda_name%:*}"

    parameters=$(jq --arg name "$latest_on_origin_prefix-file" '.DefaultBucketOnOriginRequestFunctionFromFileName = $name' <<<"$parameters")
    parameters=$(jq --arg version "$latest_on_origin_version" '.DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion = $version' <<<"$parameters")

    parameters=$(jq --arg name "$associated_lambda_name" '.DefaultBucketOnOriginRequestFunctionFromAssociationName = $name' <<<"$parameters")
    parameters=$(jq --arg version "$distro_version" '.DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion = $version' <<<"$parameters")

    parameters=$(jq '.ShouldUseFunctionFromAssociation = true' <<<"$parameters")

    echo "deploying to create $latest_on_origin_prefix-file"
    if ! deploy_stack "$parameters"; then
      exit
    fi
  fi

  parameters=$(jq --arg name "$latest_on_origin_prefix-file" '.DefaultBucketOnOriginRequestFunctionFromFileName = $name' <<<"$parameters")
  parameters=$(jq --arg version "$latest_on_origin_version" '.DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion = $version' <<<"$parameters")

  parameters=$(jq --arg name "$associated_lambda_name" '.DefaultBucketOnOriginRequestFunctionFromAssociationName = $name' <<<"$parameters")
  parameters=$(jq --arg version "$distro_version" '.DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion = $version' <<<"$parameters")

  parameters=$(jq '.ShouldUseFunctionFromAssociation = false' <<<"$parameters")

  echo 'deploy to swap which function is associated'
  if ! deploy_stack "$parameters"; then
    exit
  fi

  parameters=$(jq --arg name "$latest_on_origin_prefix-file" '.DefaultBucketOnOriginRequestFunctionFromFileName = $name' <<<"$parameters")
  parameters=$(jq --arg version "$latest_on_origin_version" '.DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion = $version' <<<"$parameters")

  parameters=$(jq --arg name "$latest_on_origin_prefix-association" '.DefaultBucketOnOriginRequestFunctionFromAssociationName = $name' <<<"$parameters")
  parameters=$(jq --arg version "$latest_on_origin_version" '.DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion = $version' <<<"$parameters")
  parameters=$(jq '.ShouldUseFunctionFromAssociation = false' <<<"$parameters")

  echo 'deploy to update the unassociated function (the previously associated function will fail to delete but the stack will update successfully)'
  if ! deploy_stack "$parameters"; then
    exit
  fi

  parameters=$(jq --arg name "$latest_on_origin_prefix-file" '.DefaultBucketOnOriginRequestFunctionFromFileName = $name' <<<"$parameters")
  parameters=$(jq --arg version "$latest_on_origin_version" '.DefaultBucketOnOriginRequestFunctionFromFileSemanticVersion = $version' <<<"$parameters")

  parameters=$(jq --arg name "$latest_on_origin_prefix-association" '.DefaultBucketOnOriginRequestFunctionFromAssociationName = $name' <<<"$parameters")
  parameters=$(jq --arg version "$latest_on_origin_version" '.DefaultBucketOnOriginRequestFunctionFromAssociationSemanticVersion = $version' <<<"$parameters")
  parameters=$(jq '.ShouldUseFunctionFromAssociation = true' <<<"$parameters")

  echo 'deploy to get back to baseline'
  if ! deploy_stack "$parameters"; then
    exit
  fi
}

# shellcheck source=/dev/null
source "$here/shared.bash" "$stack"
main
