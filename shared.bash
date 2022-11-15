#! /bin/bash
region='us-east-1'
stack_name=abr
config_file="$(dirname "$(realpath "$0")")/.$stack_name-stack-outputs.json"
