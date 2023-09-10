#!/bin/bash

# Disable AWS CLI pager
export AWS_PAGER=""

# Check if the AWS profile is set to 'eaedfi'
if [[ "$AWS_PROFILE" != "eadata" ]]; then
    # Open Chrome with the 'Leo(Work)' profile
    open -a "Google Chrome" --args "--profile-directory='Profile 17'"

    # Switch back to iTerm2
    osascript -e 'tell application "iTerm" to activate'

    # Use expect to configure AWS SSO
    expect -c '
        spawn aws configure sso --profile eadata
        expect "SSO session name (Recommended):" { send "\r\r" }
        expect "SSO start URL \\\[https://edanalytics.awsapps.com/start#\\\]:" { send "\r\r" }
        expect "SSO region \\\[us-east-2\\\]" { send "\r\r" }
        expect "There are 2 AWS accounts available to you." { send -- "\033\[B\r" }
        expect "CLI default client Region \\\[us-east-2\\\]:" { send "\r\r" }
        expect "CLI default output format \\\[None\\\]:" { send "\r\r" }
        interact
    '

    # Set AWS_PROFILE and AWS_REGION environment variables
    eadata
fi
