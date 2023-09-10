#!/bin/bash

# Prompt for the username
read -p "Enter the username: " username

# Prompt for the public key file path
read -p "Enter the public key file path: " public_key_path

# create a new user
useradd -m -s /bin/bash "$username"

# create .ssh directory in the user's home directory
mkdir -p /home/"$username"/.ssh

# copy the public key to the authorized_keys file
cp "$public_key_path" /home/"$username"/.ssh/authorized_keys

# set the permissions for .ssh directory and authorized_keys file
chmod 700 /home/"$username"/.ssh
chmod 600 /home/"$username"/.ssh/authorized_keys

# change the owner of .ssh directory to the new user
chown -R "$username":"$username" /home/"$username"/.ssh

# grant sudo privileges
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$username"

# make sure the file is only writable by root
chmod 0440 /etc/sudoers.d/"$username"

