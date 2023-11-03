#! /bin/bash

commands=('yq' 'zip')
for command in "${commands[@]}"; do
  if ! [ -x "$(command -v "$command")" ]; then
    echo "command not found: $command"
    exit
  fi
done

# (us(-gov)?|af|ap|ca|eu|me|sa)-(north|east|south|west|central)+-\d+
region=
profile=
dry_run='false' # todo: danger, sort of. looks like its gonna get stuck in a loop
did_deploy='false'

stack='abr'
primary_subdomain="${stack}"
primary_domain='primary'
primary_tld='com'
website_subdomain='www'
website_domain='website'
website_tld='com'
template_only=false
stack_name=
account_id=
_deploy_template=

here="$(dirname "$(realpath "$0")")"
readonly here
readonly template="$here/infra.yaml"

display_help() {
  echo "
Available options:
  --dry-run=        When true, no changes are actually made
  --stack=          Defaults to '${stack}'
  --account-id=     Your AWS account id
  --template-only   Only create the template - do not actually deploy
  --primary-subdomain   Defaults to '${primary_subdomain}'
  --primary-domain      Defaults to '${primary_domain}'
  --primary-tld         Defaults to '${primary_tld}'
  --website-subdomain   Defaults to '${website_subdomain}'
  --website-domain      Defaults to '${website_domain}'
  --website-tld         Defaults to '${website_tld}'
  --hot             Equivalent to --dry-run=false
  --help            This message
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
  --template-only)
    template_only=true
    ;;
  --primary-subdomain=*)
    primary_subdomain="${opt#*=}"
    ;;
  --primary-domain=*)
    primary_domain="${opt#*=}"
    ;;
  --primary-tld=*)
    primary_tld="${opt#*=}"
    ;;
  --website-subdomain=*)
    website_subdomain="${opt#*=}"
    ;;
  --website-domain=*)
    website_domain="${opt#*=}"
    ;;
  --website-tld=*)
    website_tld="${opt#*=}"
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

get_deploy_template() {
  if [ -z "$_deploy_template" ]; then
    local _deploy_template && _deploy_template="$(mktemp)"
    readonly _deploy_template
  else
    echo "$_deploy_template"
    return 0
  fi

  local AWSCloudFrontCloudFrontOriginAccessIdentity_output_GetAtt_fields=('Id' 'S3CanonicalUserId')
  local AWSCloudFrontDistribution_output_GetAtt_fields=('DomainName' 'Id')
  local AWSIAMRole_output_GetAtt_fields=('Arn' 'RoleId')
  local AWSRoute53HostedZone_output_GetAtt_fields=('Id')
  local AWSLambdaFunction_output_GetAtt_fields=('Arn')
  local AWSLambdaVersion_output_GetAtt_fields=('Version')
  local AWSLogsLogGroup_output_GetAtt_fields=('Arn')
  local AWSCloudFrontResponseHeadersPolicy_output_GetAtt_fields=('Id' 'LastModifiedTime')
  local AWSIAMUser_output_GetAtt_fields=('Arn')
  local AWSS3Bucket_output_GetAtt_fields=('Arn' 'DomainName' 'DualStackDomainName' 'RegionalDomainName' 'WebsiteURL')
  local AWSServerlessFunction_output_GetAtt_fields=('Arn')
  local AWSCloudFrontOriginAccessControl_output_GetAtt_fields=('Id')
  local AWSCloudFrontCachePolicy_output_GetAtt_fields=('Id' 'LastModifiedTime')

  echo '{}' >"$_deploy_template"
  local outputs && outputs=$(echo '{}' | jq)
  yq '.Resources | keys[]' "$template" | while read -r resource; do
    local raw_resource && raw_resource=$(echo "$resource" | tr -d '"')
    local Ref_filter=". + {\"${raw_resource}Ref\": {\"Value\": \"!Ref $raw_resource\""
    local condition && condition="$(yq ".Resources.$raw_resource.Condition" "$template")"
    if [ 'null' != "$condition" ]; then
      Ref_filter+=",\"Condition\":$condition"
    fi
    Ref_filter+='}}'
    outputs=$(jq "$Ref_filter" <<<"$outputs")

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
      outputs=$(jq "$GetAtt_filter" <<<"$outputs")
      count=$((count + 1))
    done
    if [ "$count" == 0 ] && [ 'AWSS3BucketPolicy' != "$config" ] && [ 'AWSLambdaPermission' != "$config" ] && [ 'AWSCertificateManagerCertificate' != "$config" ]; then
      echo "abr: no config for $config!"
    fi
    local insert_filter=". + {\"Outputs\":$outputs}"
    local result && result=$(cat "$_deploy_template" | yq "$insert_filter")
    echo "$result" >"$_deploy_template"
  done
  local final_outputs && final_outputs=$(cat "$_deploy_template" | yq -y | sed -E 's/(Value: '\'')/Value: /g' | sed -E 's/^(.+)Value(.+)('\'')$/\1Value\2/g')
  echo "$final_outputs" >"$_deploy_template"
  local deploy_template && deploy_template=$(mktemp)
  cp "$template" "$deploy_template"
  echo "" >>"$deploy_template"
  local temp_file_1 && temp_file_1="$(mktemp)"
  cat "$deploy_template" "$_deploy_template" >"$temp_file_1"
  cp "$temp_file_1" "$deploy_template"
  rm "$temp_file_1" "$_deploy_template"
  echo "$deploy_template"
}

deploy_stack() {
  local parameters=$1

  on_create_arn=$(get_function_arn 'DefaultBucketObjectCreatedFunction')
  if [ -n "$on_create_arn" ]; then
    parameters=$(jq --arg arn "$on_create_arn" '.DefaultBucketObjectCreatedFunctionArn = $arn' <<<"$parameters")
  fi
  parameters=$(jq '.IsFirstRun = false' <<<"$parameters")

  jq '.' <<<"$parameters"
  local -r deploy_response=$(eval "aws cloudformation deploy \
    --region $region \
    --profile $profile \
    --stack-name $stack_name \
    --capabilities CAPABILITY_IAM \
    --template-file $(get_deploy_template) \
    --parameter-overrides $(for_update "$parameters")" 2>&1 | sed '/^$/d')
  echo "$deploy_response"

  if [ "Successfully created/updated stack - $stack_name" == "$(tail -n1 <<<"$deploy_response")" ]; then
    set_config
  elif [ "No changes to deploy. Stack $stack_name is up to date" != "$(tail -n1 <<<"$deploy_response")" ]; then
    echo 'abr: something went wrong ^^'
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
    echo "abr: no versions for function: $function. exiting early..."
    exit
  fi
  echo "$latest"
}

create_stack() {
  local -r parameters=$1
  jq '.' <<<"$parameters"
  local -r create_response=$(eval "aws cloudformation create-stack \
    --stack-name $stack_name \
    --template-body file://$(get_deploy_template) \
    --region $region \
    --profile $profile \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection \
    --parameters $(for_create "$parameters")" 2>&1 | sed '/^$/d')
  echo "$create_response"
  if [ -n "$(jq '.' <<<"$create_response" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
    echo 'abr: something went wrong ^^'
    exit
  fi

  local describe_response
  local status
  local flag=true # simulate do-while loop
  local sleep=30
  while $flag || [ 'CREATE_IN_PROGRESS' == "$status" ]; do
    if ! $flag; then
      echo "abr: sleeping for $sleep seconds..."
      sleep $sleep
      sleep=$((sleep / 2))
      if [ $sleep -lt 5 ]; then
        sleep=10
      fi
    fi
    flag=false
    describe_response=$(aws cloudformation describe-stacks \
      --stack-name="$stack_name" \
      --profile "$profile" \
      --region="$region" 2>&1 | sed '/^$/d')
    status=$(jq -r '.Stacks[0].StackStatus' <<<"$describe_response")
  done
  echo "$describe_response"
  if [ 'CREATE_COMPLETE' != "$status" ]; then
    echo 'abr: something went wrong ^^'
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
    openssl dgst -sha256 -binary "$zip_path" | openssl enc -base64 >"$dir_name/.checksum"
    checksum="$(cat "$dir_name/.checksum")"

    head_object_response=$(aws s3api head-object \
      --bucket "$bucket" \
      --key "$key" \
      --checksum-mode ENABLED \
      --profile "$profile" 2>&1 | sed '/^$/d')

    if [ 'An error occurred (404) when calling the HeadObject operation: Not Found' == "$head_object_response" ]; then
      aws s3api put-object \
        --bucket "$bucket" \
        --key "$key" \
        --body "$zip_path" \
        --checksum-sha256 "$checksum" \
        --profile "$profile" >>/dev/null
      echo "abr: uploaded $key to s3://$bucket/$key with sha256 checksum $checksum"
      rm -f "$zip_path"
    elif [ "$checksum" == "$(jq -r '.ChecksumSHA256' <<<"$head_object_response")" ]; then
      rm -f "$zip_path"
      continue
    else
      rm -f "$zip_path"
      echo "$head_object_response"
      echo "abr: local/s3 checksums do not match for $key, check the response above"
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
    echo "abr: versions are the same, chucklehead..." >&2
    exit
  fi

  local highest
  if [ -z "$version_a" ]; then
    highest="$version_b"
  fi

  if [ -z "$version_b" ]; then
    highest="$version_a"
  fi

  if [ -z "$highest" ]; then
    local a=${version_a/v/}
    a=${a//./ }
    read -r -a version_a_as_array <<<"$a"

    local b=${version_b/v/}
    b=${b//./ }
    read -r -a version_b_as_array <<<"$b"

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
  fi
  echo "$highest"
}

lambdas_to_update() {
  local arn
  local latest_version
  local to_update=
  while read -r lambda; do
    arn=$(jq -r '.arn' <<<"${lambda}")
    latest_version=$(jq -r '.latest_version' <<<"${lambda}")
    if ! lambda_in_sync "$arn" "${latest_version}"; then
      if [ -n "${to_update}" ]; then
        to_update+=" "
      fi
      to_update+=$(jq -r '.event_type' <<<"${lambda}")
    fi
  done < <(jq -c '.[]' <<<"$1")
  echo "${to_update}"
}

lambda_in_sync() {
  local -r arn=$1
  local -r latest_version=$2

  local distro_version="${arn##*_}"
  distro_version="${distro_version%:*}"
  local -r distro_version_from_name="$distro_version"
  distro_version="${distro_version/-auxiliary/}"
  distro_version="${distro_version//-/.}"
  if [ "$distro_version" == "$latest_version" ]; then
    return 0
  fi

  if [ "$distro_version" == "$(highest_version "$distro_version" "$latest_version")" ]; then
    echo "abr: distro is associated with arn '$arn' (version $distro_version), local version is '$latest_version'. refusing to update stack with lower version..."
    exit
  fi

  local name="${arn%:*}"
  name="${name##*:}"
  local -r latest_version_for_name="${latest_version//./-}"
  name="${name/$distro_version_from_name/$latest_version_for_name}"
  local -r get_function_response=$(aws lambda get-function \
    --function-name "$name" \
    --region "$region" \
    --profile "$profile" 2>&1 | sed '/^$/d')

  if [ -n "$(jq '.' <<<"$get_function_response" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
    if [[ "$get_function_response" =~ .*ResourceNotFoundException.* ]]; then
      return 1
    fi
    echo "$get_function_response"
    echo 'something went wrong ^^'
    exit
  fi

  return 0
}

main() {
  local -r latest_on_origin_request='default-bucket-on-origin-request'
  local -r latest_on_origin_request_version=$(get_latest_version "$latest_on_origin_request")
  local -r latest_on_origin_request_version_friendly="${latest_on_origin_request_version//./-}"
  local -r latest_on_origin_request_prefix="$stack_name-OnOriginRequest_$latest_on_origin_request_version_friendly"

  local -r latest_on_viewer_request='default-bucket-on-viewer-request'
  local -r latest_on_viewer_request_version=$(get_latest_version "$latest_on_viewer_request")
  local -r latest_on_viewer_request_version_friendly="${latest_on_viewer_request_version//./-}"
  local -r latest_on_viewer_request_prefix="$stack_name-OnViewerRequest_$latest_on_viewer_request_version_friendly"

  local -r latest_on_response='default-bucket-on-origin-response'
  local -r latest_on_response_version=$(get_latest_version "$latest_on_response")
  local -r latest_on_response_version_friendly="${latest_on_response_version//./-}"
  local -r latest_on_response_prefix="$stack_name-OnOriginResponse_$latest_on_response_version_friendly"

  local parameters
  parameters='{}'
  parameters=$(jq --arg value "${primary_subdomain}.${primary_domain}.${primary_tld}" '.PrimaryHostedZoneName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "*.${primary_domain}.${primary_tld}" '.PrimaryCertificateDomainName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "${website_subdomain}" '.WebsiteSubdomain = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "${website_domain}" '.WebsiteDomain = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "${website_tld}" '.WebsiteTLD = "\($value)"' <<<"$parameters")
  parameters=$(jq '.IsFirstRun = true' <<<"$parameters")

  parameters=$(jq --arg value "$(get_latest_version 'default-bucket-on-create-object')" '.DefaultBucketObjectCreatedFunctionSemanticVersion = "\($value)"' <<<"$parameters")

  parameters=$(jq '.UseAuxiliaryOriginRequestEdgeFunction = false' <<<"$parameters")
  parameters=$(jq '.UseAuxiliaryViewerRequestEdgeFunction = false' <<<"$parameters")
  parameters=$(jq '.UseAuxiliaryOriginResponseEdgeFunction = false' <<<"$parameters")

  parameters=$(jq --arg value "$latest_on_origin_request_prefix-auxiliary" '.AuxiliaryPrimaryOriginRequestEdgeFunctionName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_origin_request_prefix" '.PrimaryOriginRequestEdgeFunctionName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_origin_request_version" '.AuxiliaryPrimaryOriginRequestEdgeFunctionSemanticVersion = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_origin_request_version" '.PrimaryOriginRequestEdgeFunctionSemanticVersion = "\($value)"' <<<"$parameters")

  parameters=$(jq --arg value "$latest_on_viewer_request_prefix-auxiliary" '.AuxiliaryPrimaryViewerRequestEdgeFunctionName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_viewer_request_prefix" '.PrimaryViewerRequestEdgeFunctionName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_viewer_request_version" '.AuxiliaryPrimaryViewerRequestEdgeFunctionSemanticVersion = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_viewer_request_version" '.PrimaryViewerRequestEdgeFunctionSemanticVersion = "\($value)"' <<<"$parameters")

  parameters=$(jq --arg value "$latest_on_response_prefix-auxiliary" '.AuxiliaryPrimaryOriginResponseEdgeFunctionName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_response_prefix" '.PrimaryOriginResponseEdgeFunctionName = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_response_version" '.AuxiliaryPrimaryOriginResponseEdgeFunctionSemanticVersion = "\($value)"' <<<"$parameters")
  parameters=$(jq --arg value "$latest_on_response_version" '.PrimaryOriginResponseEdgeFunctionSemanticVersion = "\($value)"' <<<"$parameters")

  local list_resources_response
  local -r describe_response=$(aws cloudformation describe-stacks \
    --stack-name="$stack_name" \
    --profile "$profile" \
    --region="$region" 2>&1 | sed '/^$/d')
  if [ -n "$(jq '.' <<<"$describe_response" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
    if [ "$describe_response" == "An error occurred (ValidationError) when calling the DescribeStacks operation: Stack with id $stack_name does not exist" ]; then
      echo "abr: creating stack '$stack_name'..."
      if ! create_stack "$parameters"; then
        exit
      fi
    else
      echo "$describe_response"
      echo 'abr: something went wrong ^^'
      exit
    fi
  else
    local -r status="$(jq -r '.Stacks[0].StackStatus' <<<"$describe_response" 2>&1 | sed '/^$/d')"
    if [ 'ROLLBACK_COMPLETE' == "$status" ]; then
      list_resources_response=$(aws cloudformation describe-stack-resources \
        --stack-name="$stack_name" \
        --profile "$profile" \
        --region="$region" 2>&1 | sed '/^$/d')
      local -r completed_resources=$(jq -r '.StackResources[] | select(.ResourceStatus|test("^(?!DELETE).+"))' <<<"$list_resources_response")
      if [ -z "$completed_resources" ]; then
        echo 'abr: first run failed, deleting...'
        "$here"/delete-stack.bash --stack="$stack"
        echo "abr: recreating stack '$stack_name'..."
        if ! create_stack "$parameters"; then
          exit
        fi
      else
        echo "abr: drift cannot be detected because stack has status '$status'. ride or die..."
      fi
    else
      local -r detection_id=$(aws cloudformation detect-stack-drift \
        --stack-name "$stack_name" \
        --output=text \
        --profile "$profile" \
        --region "$region" 2>&1 | sed '/^$/d')

      local detect_response
      local detection_status
      local flag=true # simulate do-while loop
      while $flag || [ 'DETECTION_IN_PROGRESS' == "$detection_status" ]; do
        if ! $flag; then
          echo 'abr: drift being detected, sleeping for 5 seconds...'
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
        echo 'abr: something went wrong ^^'
        exit
      fi

      drift_status="$(jq -r '.StackDriftStatus' <<<"$detect_response")"
      if [ 'IN_SYNC' == "$drift_status" ]; then
        echo 'abr: stack is in sync...'
      else
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
  fi

  parameters=$(jq '.IsFirstRun = false' <<<"$parameters")

  local -r lambda_bucket="$account_id-$stack_name-lambda-function"
  local -r latest_on_create='default-bucket-on-create-object'
  local -r keys=(
    "$(snake_to_kabob "$latest_on_viewer_request")/$latest_on_viewer_request_version/index.js.zip"
    "$(snake_to_kabob "$latest_on_origin_request")/$latest_on_origin_request_version/index.js.zip"
    "$(snake_to_kabob "$latest_on_response")/$latest_on_response_version/index.js.zip"
    "$latest_on_create/$(get_latest_version "$latest_on_create")/index.js.zip"
  )
  for key in "${keys[@]}"; do
    head_object_response=$(aws s3api head-object --bucket "$lambda_bucket" --key "$key" --profile "$profile" 2>&1 | sed '/^$/d')
    if [ "$head_object_response" == 'An error occurred (404) when calling the HeadObject operation: Not Found' ]; then
      upload_lambda_functions
      break
    fi
  done

  if [ -z "${list_resources_response}" ]; then
    list_resources_response=$(aws cloudformation list-stack-resources \
      --region="${region}" \
      --profile "${profile}" \
      --stack "${stack_name}" | sed '/^$/d')
    if [ -n "$(jq '.' <<<"${list_resources_response}" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
      echo "${list_resources_response}"
      echo 'abr: something went wrong ^^'
      exit
    fi
  fi

  distribution_id=$(jq -r '.StackResourceSummaries[] | select(.LogicalResourceId=="PrimaryDistribution") | .PhysicalResourceId' <<<"${list_resources_response}")
  if [ -z "${distribution_id}" ] || [ 'null' == "${distribution_id}" ]; then
    echo 'abr: deploying to create distribution'
    if ! deploy_stack "${parameters}"; then
      exit
    fi
    did_deploy='true'
    list_resources_response=$(aws cloudformation list-stack-resources \
      --region="${region}" \
      --profile "${profile}" \
      --stack "${stack_name}" | sed '/^$/d')
    if [ -n "$(jq '.' <<<"${list_resources_response}" 2>&1 1>/dev/null | sed '/^$/d')" ]; then
      echo "${list_resources_response}"
      echo 'abr: something went wrong ^^'
      exit
    fi
    distribution_id=$(jq -r '.StackResourceSummaries[] | select(.LogicalResourceId=="PrimaryDistribution") | .PhysicalResourceId' <<<"${list_resources_response}")

    echo 'abr: deploying to create origin access control...'
    if ! deploy_stack "${parameters}"; then
      exit
    fi
  fi
  parameters=$(jq '.PrimaryDistributionExists = true' <<<"${parameters}")

  local associations && associations=$(aws cloudfront get-distribution-config --id "${distribution_id}" --profile "${profile}" --query="DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations")

  origin_request_lambda_association=$(jq '.Items[] | select(.EventType=="origin-request")' <<<"${associations}")
  origin_request_lambda_association_arn=$(jq -r '.LambdaFunctionARN' <<<"$origin_request_lambda_association")

  viewer_request_lambda_association=$(jq '.Items[] | select(.EventType=="viewer-request")' <<<"${associations}")
  viewer_request_lambda_association_arn=$(jq -r '.LambdaFunctionARN' <<<"$viewer_request_lambda_association")

  origin_response_lambda_association=$(jq '.Items[] | select(.EventType=="origin-response")' <<<"${associations}")
  origin_response_lambda_association_arn=$(jq -r '.LambdaFunctionARN' <<<"${origin_response_lambda_association}")

  edge_lambdas="$(jq '.' < <(echo '{"data":[]}'))"
  edge_lambdas=$( \
    jq \
      --arg arn "${origin_request_lambda_association_arn}" \
      --arg latest_version "${latest_on_origin_request_version}" \
      '.data[.data| length] |= . + { "arn":$arn, "latest_version":$latest_version, "event_type":"origin-request" }' <<<"${edge_lambdas}" \
  )
  edge_lambdas=$( \
    jq \
      --arg arn "${viewer_request_lambda_association_arn}" \
      --arg latest_version "${latest_on_viewer_request_version}" \
      '.data[.data| length] |= . + { "arn":$arn, "latest_version":$latest_version, "event_type":"viewer-request" }' <<<"${edge_lambdas}" \
  )
 edge_lambdas=$( \
    jq \
      --arg arn "${origin_response_lambda_association_arn}" \
      --arg latest_version "${latest_on_response_version}" \
      '.data[.data| length] |= . + { "arn":$arn, "latest_version":$latest_version, "event_type":"origin-request" }' <<<"${edge_lambdas}" \
  )

  edge_lambdas=$(jq  '.data' <<<"${edge_lambdas}")

  # TODO change the non-auxiliary back to the one that is associated if it does not need to be updated
  # assuming you dont want to just forget about the auxiliary all together by using the update/delete policy thing

  local -r to_update=$(lambdas_to_update "${edge_lambdas}")
  if [ -z "${to_update}" ] && [ "${did_deploy}" == 'false' ]; then
    echo 'abr: deploying because this command should always deploy at least once...'
    if deploy_stack "${parameters}"; then
      echo 'abr: done without errors...'
    fi
    exit
  fi
  read -r -a to_update_as_array <<<"${to_update}"

  echo 'abr: deploying to create new function(s)'
  # fixme: on create this is the last necessary deploy
  if ! deploy_stack "${parameters}"; then
    exit
  fi

  # todo: change lambda to event_type
  for lambda in "${to_update_as_array[@]}"; do
    the_key="UseAuxiliary$(kabob_to_pascal "$lambda")EdgeFunction"
    parameters=$(jq --arg key "$the_key" '."\($key)" = true' <<<"$parameters")
  done

  echo 'abr: deploy to swap which function is associated...'
  if ! deploy_stack "$parameters"; then
    exit
  fi

  for lambda in "${to_update_as_array[@]}"; do
    dumb_on_blah="default-bucket-on-${lambda}"
    dumb_on_blah_version=$(get_latest_version "${dumb_on_blah}")
    dumb_on_blah_version_friendly="${dumb_on_blah_version//./-}"
    dumb_on_blah_prefix="$stack_name-On$(kabob_to_pascal "${lambda}")_${dumb_on_blah_version_friendly}"
    the_key="Primary$(kabob_to_pascal "$lambda")EdgeFunctionName"
    parameters=$(jq --arg key "$the_key" --arg value "$dumb_on_blah_prefix" '."\($key)" = $value' <<<"$parameters")
    the_key="Primary$(kabob_to_pascal "$lambda")EdgeFunctionSemanticVersion"
    parameters=$(jq --arg key "$the_key" --arg value "$dumb_on_blah_version" '."\($key)" = $value' <<<"$parameters")
  done
  echo 'abr: deploy to update the unassociated function...'
  if ! deploy_stack "$parameters"; then
    exit
  fi

  for lambda in "${to_update_as_array[@]}"; do
    the_key="UseAuxiliary$(kabob_to_pascal "$lambda")EdgeFunction"
    parameters=$(jq --arg key "$the_key" '."\($key)" = false' <<<"$parameters")
  done
  echo 'abr: deploy to get back to baseline...'
  if ! deploy_stack "$parameters"; then
    exit
  fi
}

# shellcheck source=/dev/null
source "$here/shared.bash" "$stack"
get_deploy_template &>/dev/null
if [ $template_only == false ]; then
  main
else
  cat "$(get_deploy_template)" && printf "\n the above template is at %s\n" "$(get_deploy_template)" || printf 'something went wrong.\n\n'
fi

