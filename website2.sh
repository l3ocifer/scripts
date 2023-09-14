#!/bin/bash

# Check if AWS CLI is available
if ! command -v aws &> /dev/null
then
    echo "AWS CLI is not installed or not in the PATH. Please install it and try again."
    exit 1
fi

# Check if Terraform is available
if ! command -v terraform &> /dev/null
then
    echo "Terraform is not installed or not in the PATH. Please install it and try again."
    exit 1
fi

# Check for DOMAIN_NAME environment variable or prompt the user
if [[ -z "${DOMAIN_NAME}" ]]; then
    read -p "Please enter your domain name (e.g., example.com): " DOMAIN_NAME
fi

# Fetch hosted zone ID for the provided domain name
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text | cut -d'/' -f3)

if [[ -z "${ZONE_ID}" ]]; then
    echo "Unable to find a hosted zone for the domain: $DOMAIN_NAME"
    exit 1
fi

# Fetch the ACM certificate ARN for the provided domain name
CERT_ARN=$(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='${DOMAIN_NAME}'].CertificateArn" --output text)

if [[ -z "${CERT_ARN}" ]]; then
    echo "Unable to find an ACM certificate for the domain: $DOMAIN_NAME"
    exit 1
fi

# Generate the Terraform configuration
cat > main.tf <<EOF
provider "aws" {
  region = "us-west-2"
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = "${DOMAIN_NAME}"
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.website_bucket.id
  acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }
}


resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "arn:aws:s3:::${DOMAIN_NAME}/*"
    }]
  })
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id   = "${DOMAIN_NAME}"

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${DOMAIN_NAME}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = "${CERT_ARN}"
    ssl_support_method       = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "s3-distribution"
  }
}

resource "aws_route53_record" "www" {
  zone_id = "${ZONE_ID}"
  name    = "${DOMAIN_NAME}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

output "s3_bucket_endpoint" {
  value = aws_s3_bucket.website_bucket.bucket_regional_domain_name
}

output "cloudfront_distribution_url" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
EOF

# Initialize Terraform and apply the configuration
terraform init
terraform apply
