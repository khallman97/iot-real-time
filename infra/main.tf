# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iot_endpoint" "iot" {
  endpoint_type = "iot:Data-ATS"
}

# -----------------------------------------------------------------------------
# DynamoDB Tables
# -----------------------------------------------------------------------------

# Equipment Registry - Maps serial numbers to companies
resource "aws_dynamodb_table" "equipment_registry" {
  name           = "${var.project_name}-equipment-registry"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "serial_number"

  attribute {
    name = "serial_number"
    type = "S"
  }

  # GSI to query equipment by company
  global_secondary_index {
    name            = "company-index"
    hash_key        = "company_id"
    projection_type = "ALL"
    read_capacity   = var.dynamodb_read_capacity
    write_capacity  = var.dynamodb_write_capacity
  }

  attribute {
    name = "company_id"
    type = "S"
  }
}

# Sensor Data - Historical sensor readings
resource "aws_dynamodb_table" "sensor_data" {
  name           = "${var.project_name}-sensor-data"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "serial_number"
  range_key      = "timestamp"

  attribute {
    name = "serial_number"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for IoT Core Rules
# -----------------------------------------------------------------------------

resource "aws_iam_role" "iot_rule_role" {
  name = "${var.project_name}-iot-rule-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "iot_rule_policy" {
  name = "${var.project_name}-iot-rule-policy"
  role = aws_iam_role.iot_rule_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow writing to sensor data table
        Action = [
          "dynamodb:PutItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.sensor_data.arn
      },
      {
        # Allow reading from equipment registry (for company lookup)
        Action = [
          "dynamodb:GetItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.equipment_registry.arn
      },
      {
        # Allow republishing to company topics
        Action = [
          "iot:Publish"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/companies/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IoT Core Topic Rule - Multi-tenant Router
# -----------------------------------------------------------------------------

resource "aws_iot_topic_rule" "multi_tenant_router" {
  name        = "${replace(var.project_name, "-", "_")}_router"
  description = "Routes incoming sensor data to company-specific topics and stores in DynamoDB"
  enabled     = true
  sql_version = "2016-03-23"

  sql = <<-EOF
    SELECT
      *,
      topic(2) as serial_number,
      timestamp() as server_timestamp
    FROM 'raw/+'
    WHERE NOT isUndefined(
      get_dynamodb(
        "${aws_dynamodb_table.equipment_registry.name}",
        "serial_number",
        topic(2),
        "${aws_iam_role.iot_rule_role.arn}"
      ).company_id
    )
  EOF

  # Action 1: Store to DynamoDB
  dynamodbv2 {
    role_arn   = aws_iam_role.iot_rule_role.arn
    put_item {
      table_name = aws_dynamodb_table.sensor_data.name
    }
  }

  # Action 2: Republish to company-specific topic
  republish {
    role_arn = aws_iam_role.iot_rule_role.arn
    topic    = "companies/$${get_dynamodb('${aws_dynamodb_table.equipment_registry.name}', 'serial_number', topic(2), '${aws_iam_role.iot_rule_role.arn}').company_id}/$${topic(2)}"
    qos      = 1
  }

  # Error action - log to CloudWatch
  error_action {
    cloudwatch_logs {
      log_group_name = aws_cloudwatch_log_group.iot_errors.name
      role_arn       = aws_iam_role.iot_rule_role.arn
    }
  }
}

# CloudWatch Log Group for IoT Rule errors
resource "aws_cloudwatch_log_group" "iot_errors" {
  name              = "/aws/iot/${var.project_name}/errors"
  retention_in_days = 14
}

# Add CloudWatch Logs permission to IoT role
resource "aws_iam_role_policy" "iot_rule_cloudwatch_policy" {
  name = "${var.project_name}-iot-cloudwatch-policy"
  role = aws_iam_role.iot_rule_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.iot_errors.arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Cognito User Pool
# -----------------------------------------------------------------------------

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool"

  # Username configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  # Custom attributes
  schema {
    name                     = "company_id"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  read_attributes  = ["email", "custom:company_id"]
  write_attributes = ["email"]
}

# -----------------------------------------------------------------------------
# Cognito Identity Pool
# -----------------------------------------------------------------------------

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.project_name}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }
}

# IAM Role for authenticated users
resource "aws_iam_role" "cognito_authenticated" {
  name = "${var.project_name}-cognito-authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:TagSession"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
        }
      }
    ]
  })
}

# IAM Policy for authenticated users - IoT access
# TEMPORARY: Using wildcards to debug connection issues
# TODO: Restore principal tag restrictions after confirming connection works
resource "aws_iam_role_policy" "cognito_authenticated_iot" {
  name = "${var.project_name}-cognito-iot-policy"
  role = aws_iam_role.cognito_authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow connecting to IoT with any client ID
        Action   = "iot:Connect"
        Effect   = "Allow"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/*"
      },
      {
        # Allow subscribing to company topics
        Action   = "iot:Subscribe"
        Effect   = "Allow"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/companies/*"
      },
      {
        # Allow receiving messages from company topics
        Action   = "iot:Receive"
        Effect   = "Allow"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/companies/*"
      }
    ]
  })
}

# IAM Policy for authenticated users - Lambda/API access
resource "aws_iam_role_policy" "cognito_authenticated_api" {
  name = "${var.project_name}-cognito-api-policy"
  role = aws_iam_role.cognito_authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "lambda:InvokeFunctionUrl"
        Effect   = "Allow"
        Resource = aws_lambda_function.history_api.arn
      }
    ]
  })
}

# Identity Pool Role Attachment with principal tag mapping
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    authenticated = aws_iam_role.cognito_authenticated.arn
  }

  role_mapping {
    identity_provider         = "${aws_cognito_user_pool.main.endpoint}:${aws_cognito_user_pool_client.main.id}"
    ambiguous_role_resolution = "AuthenticatedRole"
    type                      = "Token"
  }
}

# Principal tag mapping - maps Cognito custom:company_id to AWS principal tag
# The identity_provider_name should match the provider_name in cognito_identity_providers
resource "aws_cognito_identity_pool_provider_principal_tag" "main" {
  identity_pool_id       = aws_cognito_identity_pool.main.id
  identity_provider_name = aws_cognito_user_pool.main.endpoint
  use_defaults           = false

  principal_tags = {
    "company_id" = "custom:company_id"
  }

  depends_on = [aws_cognito_identity_pool.main]
}

# -----------------------------------------------------------------------------
# Lambda Function - History API
# -----------------------------------------------------------------------------

data "archive_file" "history_api" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/history_service"
  output_path = "${path.module}/.build/history_api.zip"
}

resource "aws_lambda_function" "history_api" {
  function_name    = "${var.project_name}-history-api"
  filename         = data.archive_file.history_api.output_path
  source_code_hash = data.archive_file.history_api.output_base64sha256
  handler          = "index.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_history_api.arn
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      SENSOR_DATA_TABLE      = aws_dynamodb_table.sensor_data.name
      EQUIPMENT_REGISTRY_TABLE = aws_dynamodb_table.equipment_registry.name
    }
  }
}

# -----------------------------------------------------------------------------
# API Gateway (HTTP API with Cognito JWT Authorizer)
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_headers     = ["Authorization", "Content-Type"]
    allow_credentials = false
    max_age           = 86400
  }
}

# Cognito JWT Authorizer
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
    issuer   = "https://${aws_cognito_user_pool.main.endpoint}"
  }
}

# Lambda integration
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.history_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "equipment" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /equipment"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "history" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /history"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  # No auth required for health check
}

# Route for attaching IoT policy (JWT protected)
resource "aws_apigatewayv2_route" "attach_iot_policy" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /attach-iot-policy"
  target             = "integrations/${aws_apigatewayv2_integration.attach_iot_policy.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Integration for attach IoT policy Lambda
resource "aws_apigatewayv2_integration" "attach_iot_policy" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.attach_iot_policy.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Permission for API Gateway to invoke attach IoT policy Lambda
resource "aws_lambda_permission" "api_gateway_attach_iot" {
  statement_id  = "AllowAPIGatewayInvokeAttachIot"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.attach_iot_policy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Default stage with auto-deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.history_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_history_api" {
  name = "${var.project_name}-lambda-history-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda basic execution role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_history_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda DynamoDB access policy
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb"
  role = aws_iam_role.lambda_history_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Effect = "Allow"
        Resource = [
          aws_dynamodb_table.sensor_data.arn,
          aws_dynamodb_table.equipment_registry.arn,
          "${aws_dynamodb_table.equipment_registry.arn}/index/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IoT Thing (for simulator - optional, can create via CLI)
# -----------------------------------------------------------------------------

resource "aws_iot_thing" "simulator" {
  name = "${var.project_name}-simulator"
}

resource "aws_iot_policy" "simulator" {
  name = "${var.project_name}-simulator-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "iot:Connect"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "iot:Publish"
        Effect   = "Allow"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/raw/*"
      }
    ]
  })
}

# IoT Policy for Cognito-authenticated web users
# This policy is attached to the Cognito Identity via Lambda post-auth trigger
resource "aws_iot_policy" "cognito_web_user" {
  name = "${var.project_name}-cognito-web-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/*"
      },
      {
        Effect   = "Allow"
        Action   = "iot:Subscribe"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/companies/*"
      },
      {
        Effect   = "Allow"
        Action   = "iot:Receive"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/companies/*"
      }
    ]
  })
}

# Lambda function to attach IoT policy to Cognito Identity
resource "aws_lambda_function" "attach_iot_policy" {
  function_name = "${var.project_name}-attach-iot-policy"
  runtime       = "python3.11"
  handler       = "index.handler"
  role          = aws_iam_role.attach_iot_policy_role.arn
  timeout       = 10

  filename         = data.archive_file.attach_iot_policy_zip.output_path
  source_code_hash = data.archive_file.attach_iot_policy_zip.output_base64sha256

  environment {
    variables = {
      IOT_POLICY_NAME = aws_iot_policy.cognito_web_user.name
    }
  }
}

# Package Lambda code
data "archive_file" "attach_iot_policy_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/attach_iot_policy/index.py"
  output_path = "${path.module}/../backend/attach_iot_policy.zip"
}

# IAM role for the attach IoT policy Lambda
resource "aws_iam_role" "attach_iot_policy_role" {
  name = "${var.project_name}-attach-iot-policy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for attach IoT policy Lambda
resource "aws_iam_role_policy" "attach_iot_policy_permissions" {
  name = "${var.project_name}-attach-iot-policy-permissions"
  role = aws_iam_role.attach_iot_policy_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:AttachPolicy",
          "iot:ListAttachedPolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

# Allow Cognito to invoke the Lambda
resource "aws_lambda_permission" "cognito_attach_iot_policy" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.attach_iot_policy.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

# -----------------------------------------------------------------------------
# S3 + CloudFront Static Hosting for Frontend
# -----------------------------------------------------------------------------

# S3 bucket for frontend static files
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${data.aws_caller_identity.current.account_id}"
}

# Block public access (CloudFront will access via OAC)
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-frontend-oac"
  description                       = "OAC for frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project_name} frontend"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Handle SPA routing - return index.html for 404s
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}
