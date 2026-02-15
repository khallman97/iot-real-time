# Infrastructure (Terraform)

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials

## Commands

### Initialize (first time only)

```bash
terraform init
```

### Preview changes

```bash
terraform plan
```

### Deploy

```bash
terraform apply
```

After deployment, copy the `frontend_config` output to your frontend config file.

### Update

Make changes to `.tf` files, then:

```bash
terraform plan    # Preview changes
terraform apply   # Apply changes
```

### Destroy

```bash
terraform destroy
```

**Warning:** This deletes all resources including DynamoDB tables and their data.

## Configuration

Edit `variables.tf` to change defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `ca-central-1` | AWS region |
| `project_name` | `iot-monitoring` | Resource naming prefix |
| `environment` | `dev` | Environment tag |
| `dynamodb_read_capacity` | `5` | DynamoDB RCU |
| `dynamodb_write_capacity` | `5` | DynamoDB WCU |

Or override at runtime:

```bash
terraform apply -var="aws_region=us-east-1"
```

## Outputs

After `terraform apply`, you'll see:

- `iot_endpoint` - IoT Core MQTT endpoint
- `cognito_user_pool_id` - For creating users
- `cognito_identity_pool_id` - For frontend auth
- `history_api_url` - Lambda API endpoint
- `frontend_config` - Copy-paste ready config for frontend
