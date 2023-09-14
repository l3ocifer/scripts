#!/bin/bash

# Check for the STACK_S3_URL environment variable
if [[ -z "$STACK_S3_URL" ]]; then
    # If not set, prompt the user
    echo "STACK_S3_URL environment variable not set."
    read -p "Please provide the Template URL (S3 URL): " STACK_S3_URL
fi

# Get the details of the most recently created/updated stack
STACK_INFO=$(aws cloudformation describe-stacks --query "Stacks | sort_by(@, &CreationTime) | [-1]" --output json)

# Extract the StackName from STACK_INFO using Python
CURRENT_STACK_NAME=$(python -c "import json; data = json.loads('''$STACK_INFO'''); print(data['StackName'])")

# Check if the stack name ends with -<number> and generate the new stack name
if [[ $CURRENT_STACK_NAME =~ (.*-)([0-9]+)$ ]]; then
    BASE_NAME=${BASH_REMATCH[1]}
    CURRENT_NUMBER=${BASH_REMATCH[2]}
    NEW_STACK_NAME="${BASE_NAME}$((CURRENT_NUMBER + 1))"
else
    NEW_STACK_NAME="${CURRENT_STACK_NAME}-1"
fi

# Parse with Python and construct the command
CMD=$(python - <<END
import json
import sys

NEW_STACK_NAME = "$NEW_STACK_NAME"


data = json.loads('''$STACK_INFO''')
stack = data

# Extract details
template_url = "$STACK_S3_URL"

# Include parameters even if they have an empty value, and wrap ParameterValue in quotes
parameters = " ".join([
    'ParameterKey={},ParameterValue="{}"'.format(p["ParameterKey"], p["ParameterValue"])
    for p in stack.get("Parameters", [])
])

capabilities = " ".join(stack.get("Capabilities", []))
role_arn = stack.get("RoleARN", "")
disable_rollback = str(stack.get("DisableRollback", "")).lower()
timeout_in_minutes = stack.get("TimeoutInMinutes", "")
on_failure = stack.get("OnFailure", "")
stack_policy_body = stack.get("StackPolicyBody", "")
stack_policy_url = stack.get("StackPolicyURL", "")

# Construct the command
cmd_parts = [
    "aws cloudformation create-stack",
    "--stack-name {}".format(NEW_STACK_NAME),
    "--template-url {}".format(template_url),
    "--parameters {}".format(parameters),
    "--capabilities {}".format(capabilities)
]

if role_arn:
    cmd_parts.append("--role-arn {}".format(role_arn))
if disable_rollback == "true":
    cmd_parts.append("--disable-rollback")
if timeout_in_minutes:
    cmd_parts.append("--timeout-in-minutes {}".format(timeout_in_minutes))
if on_failure:
    cmd_parts.append("--on-failure {}".format(on_failure))
if stack_policy_body:
    cmd_parts.append("--stack-policy-body '{}'".format(stack_policy_body))
if stack_policy_url:
    cmd_parts.append("--stack-policy-url {}".format(stack_policy_url))

cmd = " ".join(cmd_parts)
print(cmd)
END
"$NEW_STACK_NAME"
)

# Print the command and copy to clipboard
echo "$CMD" | tee >(pbcopy)
