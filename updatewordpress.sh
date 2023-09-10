#!/bin/bash

set -e

#cd to ursulai/infra root
cd . || exit

# Step 1: Create a php.ini file with the required settings - any needed additional file
mkdir docker
cat << EOF > docker/php.ini
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 300
EOF

# Step 2: Create a Dockerfile
cat << EOF > docker/Dockerfile
# Use an official WordPress runtime as a parent image
FROM wordpress:latest as builder

# Set the working directory
WORKDIR /var/www/html

# Copy the wp-content directory into the container
COPY wp-content/ /var/www/html/wp-content

# Copy the php.ini file into the container
COPY php.ini /usr/local/etc/php/conf.d/uploads.ini

# Start a new, final image to reduce size
FROM wordpress:latest

# Copy the built site from the builder stage
COPY --from=builder /var/www/html/wp-content /var/www/html/wp-content

# Copy the php.ini file from the builder stage
COPY --from=builder /usr/local/etc/php/conf.d/uploads.ini /usr/local/etc/php/conf.d/uploads.ini

# Set the working directory
WORKDIR /var/www/html

# Set up healthcheck
HEALTHCHECK CMD curl --fail http://localhost:80 || exit 1

# Expose port 80
EXPOSE 80
EOF

# Apply Terraform configuration
cd terraform/ || exit
terraform init
terraform apply -auto-approve

# Update Kubeconfig
AWS_REGION=$(aws configure get region)
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

# Get the ECR repository URL
ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)

# Authenticate Docker with ECR
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URL}

# Step 3: Build the Docker image and push it to ECR
# Get ECR login password
PASSWORD=$(aws ecr get-login-password --region us-east-1)

# Login to ECR
echo $PASSWORD | docker login --username AWS --password-stdin $ECR_REPOSITORY_URL

##move to root folder
cd ../ || exit

# Build the Docker image
docker build -t my-wordpress docker/

# Tag the Docker image
docker tag my-wordpress:latest $ECR_REPOSITORY_URL:latest

# Push the Docker image
docker push $ECR_REPOSITORY_URL:latest

# Clean up the Docker and php.ini files
rm -rf docker/

# Step 4: Update the Kubernetes deployment
cat << EOF > kubernetes/wordpress-deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wordpress
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
        - name: wordpress
          image: $ECR_REPOSITORY_URL:latest
          env:
            - name: WORDPRESS_DB_HOST
              valueFrom:
                secretKeyRef:
                  name: wordpress-secrets
                  key: endpoint
            - name: WORDPRESS_DB_NAME
              valueFrom:
                secretKeyRef:
                  name: wordpress-secrets
                  key: name
            - name: WORDPRESS_DB_USER
              valueFrom:
                secretKeyRef:
                  name: wordpress-secrets
                  key: user
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: wordpress-secrets
                  key: password
          ports:
            - containerPort: 80
              name: wordpress
          volumeMounts:
            - name: wordpress-persistent-storage
              mountPath: /var/www/html
      volumes:
      - name: wordpress-persistent-storage
        persistentVolumeClaim:
          claimName: wp-pv-claim
EOF

# Apply the updated deployment
kubectl apply -f kubernetes/wordpress-deployment.yml
