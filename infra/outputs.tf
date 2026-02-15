# -----------------------------------------------------------------------------
# Outputs - Use these to configure your frontend and simulators
# -----------------------------------------------------------------------------

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# IoT Core
output "iot_endpoint" {
  description = "IoT Core endpoint for MQTT connections"
  value       = data.aws_iot_endpoint.iot.endpoint_address
}

output "iot_endpoint_wss" {
  description = "IoT Core WebSocket endpoint for frontend"
  value       = "wss://${data.aws_iot_endpoint.iot.endpoint_address}/mqtt"
}

# Cognito
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = aws_cognito_identity_pool.main.id
}

# API Gateway
output "api_gateway_url" {
  description = "API Gateway URL for History API"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

# DynamoDB
output "equipment_registry_table" {
  description = "DynamoDB Equipment Registry table name"
  value       = aws_dynamodb_table.equipment_registry.name
}

output "sensor_data_table" {
  description = "DynamoDB Sensor Data table name"
  value       = aws_dynamodb_table.sensor_data.name
}

# IoT Thing (for simulator)
output "simulator_thing_name" {
  description = "IoT Thing name for simulator"
  value       = aws_iot_thing.simulator.name
}

output "simulator_policy_name" {
  description = "IoT Policy name for simulator"
  value       = aws_iot_policy.simulator.name
}

# Frontend Config (copy-paste ready)
output "frontend_config" {
  description = "Configuration for frontend (copy to frontend/src/config.js)"
  value = <<-EOF

    // Copy this to frontend/src/config.js
    export const awsConfig = {
      region: "${var.aws_region}",
      iotEndpoint: "wss://${data.aws_iot_endpoint.iot.endpoint_address}/mqtt",
      apiUrl: "${aws_apigatewayv2_api.main.api_endpoint}",
      cognitoUserPoolId: "${aws_cognito_user_pool.main.id}",
      cognitoClientId: "${aws_cognito_user_pool_client.main.id}",
      cognitoIdentityPoolId: "${aws_cognito_identity_pool.main.id}"
    };

  EOF
}

# Frontend Hosting
output "frontend_bucket" {
  description = "S3 bucket for frontend files"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_url" {
  description = "CloudFront URL for the frontend"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.frontend.id
}

# Deployment commands
output "deploy_frontend_commands" {
  description = "Commands to deploy frontend"
  value = <<-EOF

    # Build and deploy frontend:
    cd frontend
    npm run build
    aws s3 sync dist/ s3://${aws_s3_bucket.frontend.id} --delete
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.frontend.id} --paths "/*"

  EOF
}
