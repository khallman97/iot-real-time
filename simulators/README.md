# Simulators

Scripts for testing the IoT pipeline.

## Prerequisites

```bash
pip install boto3 AWSIoTPythonSDK
```

## 1. Seed Equipment Registry

Populates DynamoDB with 5 demo equipment across 3 companies.

```bash
python seed_registry.py
```

To use a different table or region:

```bash
AWS_REGION=us-east-1 EQUIPMENT_REGISTRY_TABLE=my-table python seed_registry.py
```

### Remove seed data

Use AWS CLI or Console to delete items, or just run `terraform destroy` to remove the table entirely.

## 2. Fake Equipment Simulator

Sends MQTT sensor data to IoT Core.

### Setup certificates (one-time)

```bash
# Create certificate
aws iot create-keys-and-certificate --set-as-active \
  --certificate-pem-outfile device_cert/device.pem.crt \
  --private-key-outfile device_cert/private.pem.key

# Attach policy (use certificate ARN from previous command)
aws iot attach-policy \
  --policy-name iot-monitoring-simulator-policy \
  --target arn:aws:iot:ca-central-1:123456789:cert/xxxxx

# Download root CA
curl -o device_cert/AmazonRootCA1.pem \
  https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

### Run simulator

```bash
# Get your IoT endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS

# Run (replace with your endpoint)
python fake_equipment.py --endpoint xxxxx-ats.iot.ca-central-1.amazonaws.com
```

Or set environment variable:

```bash
export IOT_ENDPOINT=xxxxx-ats.iot.ca-central-1.amazonaws.com
python fake_equipment.py
```

### Options

```bash
python fake_equipment.py --help

--endpoint    IoT Core endpoint
--interval    Seconds between readings (default: 5)
--equipment   Equipment IDs to simulate (default: EQ-001 through EQ-005)
```

### Cleanup certificates

```bash
# List certificates
aws iot list-certificates

# Detach policy, deactivate, and delete
aws iot detach-policy --policy-name iot-monitoring-simulator-policy --target <cert-arn>
aws iot update-certificate --certificate-id <cert-id> --new-status INACTIVE
aws iot delete-certificate --certificate-id <cert-id>
```
