#!/bin/bash

# Check if KEY_PATH is set
if [ -z "$KEY_PATH" ]; then
    echo "KEY_PATH is not set"
    exit 5
fi

# Variables – change if needed
BASTION_USER=ubuntu
BASTION_IP=18.188.174.40    #bastion's public IP
TARGET_USER=ubuntu
TARGET_IP=10.0.0.135         #Polybot's private IP


ssh -i "$KEY_PATH" -o ProxyCommand="ssh -i $KEY_PATH -W %h:%p $BASTION_USER@$BASTION_IP" $TARGET_USER@$TARGET_IP
