#!/bin/zsh

# Prompt user for action
echo "Add an (a)lias or (e)nvironment variable to .zshrc?"
read -k 1 input < /dev/tty

# If user selects 'a' for alias
if [ "$input" = "a" ]; then
    # Prompt for alias name and command
    echo -e "\nEnter alias name: "
    read alias_name < /dev/tty
    echo -e "Enter alias command: "
    read alias_command < /dev/tty

    # Append alias command to .zshrc
    new_alias="alias $alias_name='$alias_command'"
    echo $new_alias >> ~/.zshrc
    echo -e "\nAlias created: $new_alias"

# If user selects 'e' for environment variable
elif [ "$input" = "e" ]; then
    # Prompt for variable name and value
    echo -e "\nEnter variable name: "
    read var_name < /dev/tty
    echo -e "Enter variable value: "
    read var_value < /dev/tty

    # Append export command to .zshrc
    new_export="export $var_name='$var_value'"
    echo $new_export >> ~/.zshrc
    echo -e "\nVariable exported: $new_export"

else
    echo -e "\nInvalid input. Please enter either 'a' or 'e'."
    exit 1
fi

# Reload .zshrc file
source ~/.zshrc
echo -e "\nThe .zshrc file has been reloaded."

