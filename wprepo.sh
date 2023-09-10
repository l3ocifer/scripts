#!/bin/bash

set -e

# Create the directory structure
mkdir -p wordpress/wp-content/plugins
mkdir -p wordpress/wp-content/themes
mkdir -p wordpress/client

# Check if directories were created successfully
if [ ! -d "wordpress/wp-content/plugins" ] || [ ! -d "wordpress/wp-content/themes" ] || [ ! -d "wordpress/client" ]; then
    echo "Directory creation failed"
    exit 1
fi

# Create the Dockerfile
cat << EOF > wordpress/Dockerfile
FROM wordpress:latest

# Copy the wp-content directory into the container
COPY wp-content/ /var/www/html/wp-content

# Set the working directory
WORKDIR /var/www/html

# Expose port 80
EXPOSE 80
EOF

# Check if Dockerfile was created successfully
if [ ! -f "wordpress/Dockerfile" ]; then
    echo "Dockerfile creation failed"
    exit 1
fi

# Create the docker-compose.yml file
cat << EOF > wordpress-docker/docker-compose.yml
version: '3.3'

services:
 db:
   image: postgres:latest
   volumes:
     - db_data:/var/lib/postgresql/data
   restart: always
   environment:
     POSTGRES_PASSWORD: mysecretpassword

 wordpress:
   depends_on:
     - db
   image: wordpress:latest
   ports:
     - "8000:80"
   restart: always
   environment:
     WORDPRESS_DB_HOST: db:5432
     WORDPRESS_DB_USER: postgres
     WORDPRESS_DB_PASSWORD: mysecretpassword

 client:
   build: https://github.com/ursulai/ursulai-landing.git
   ports:
     - "3000:3000"
   depends_on:
     - wordpress
   volumes:
     - ./client:/usr/src/app
     - /usr/src/app/node_modules
   environment:
     - NODE_ENV=development
   command: ["npm", "start"]

volumes:
   db_data: {}
EOF


# Check if docker-compose.yml was created successfully
if [ ! -f "wordpress/docker-compose.yml" ]; then
    echo "docker-compose.yml creation failed"
    exit 1
fi
