#!/bin/bash

# move back to repo root
cd $REPO_PATH
# Initialize a new git repository in the directory from which the script is run, only if it hasn't been initialized already
if [ ! -d ".git" ]; then
    git init

    # Add a .gitignore suitable for React and Terraform
    cat << EOF > .gitignore
    # React
    $DOMAINNAME/node_modules/
    $DOMAINNAME/build/
    *.log

    # Terraform
    **/.terraform/
    *.tfstate
    *.tfstate.backup
    *.tfvars

    # Misc
    *.DS_Store
EOF

    # Make an initial commit
    git add .
    git commit -m "Initial commit"

    # Create a new GitHub repository (You need to set GITHUB_TOKEN as an environment variable)
    REPO_NAME="website-$DOMAINNAME"
    curl -H "Authorization: token $GITHUB_ACCESS_TOKEN" --data '{"name":"'$REPO_NAME'"}' https://api.github.com/user/repos

    # Link to remote and push
    git remote add origin "https://github.com/l3ocifer/$REPO_NAME.git"
    git branch -M main
    git push -u origin main
fi
