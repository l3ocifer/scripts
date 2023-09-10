#!/bin/bash

for dir in */ ; do
    echo "Entering ${dir}"
    cd "${dir}"
    git pull
    cd ..
done

