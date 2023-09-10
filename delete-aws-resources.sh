#!/bin/bash

# Get the current region from the AWS profile
REGION=$(aws configure get region)

# Delete network interfaces
ENI_IDS=$(aws ec2 describe-network-interfaces --region "${REGION}" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)

for eni_id in ${ENI_IDS}; do
  ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region "${REGION}" --network-interface-ids "${eni_id}" --query 'NetworkInterfaces[0].Attachment.AttachmentId' 
--output text)

  if [[ "${ATTACHMENT_ID}" != "None" ]]; then
    aws ec2 detach-network-interface --region "${REGION}" --attachment-id "${ATTACHMENT_ID}" --force
  fi

  aws ec2 delete-network-interface --region "${REGION}" --network-interface-id "${eni_id}"
done

# Delete subnets
SUBNET_IDS=$(aws ec2 describe-subnets --region "${REGION}" --query 'Subnets[].SubnetId' --output text)

for subnet_id in ${SUBNET_IDS}; do
  aws ec2 delete-subnet --region "${REGION}" --subnet-id "${subnet_id}"
done

# Delete security groups
SECURITY_GROUP_IDS=$(aws ec2 describe-security-groups --region "${REGION}" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)

for sg_id in ${SECURITY_GROUP_IDS}; do
  aws ec2 delete-security-group --region "${REGION}" --group-id "${sg_id}"
done

# Detach and delete internet gateways
INTERNET_GATEWAY_IDS=$(aws ec2 describe-internet-gateways --region "${REGION}" --query 'InternetGateways[].InternetGatewayId' --output text)

for igw_id in ${INTERNET_GATEWAY_IDS}; do
  VPC_IDS=$(aws ec2 describe-internet-gateways --region "${REGION}" --internet-gateway-ids "${igw_id}" --query 'InternetGateways[0].Attachments[].VpcId' --output text)

  for vpc_id in ${VPC_IDS}; do
    aws ec2 detach-internet-gateway --region "${REGION}" --internet-gateway-id "${igw_id}" --vpc-id "${vpc_id}"
  done

  aws ec2 delete-internet-gateway --region "${REGION}" --internet-gateway-id "${igw_id}"
done

