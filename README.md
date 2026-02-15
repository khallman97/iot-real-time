# Real-Time IoT Monitoring

A multi-tenant IoT monitoring platform that ingests sensor data via MQTT, stores it in DynamoDB, and displays real-time updates on a web dashboard. Built on AWS Free Tier services using Terraform.

## Architecture Overview

```
                                    ┌─────────────────┐
                                    │  DynamoDB       │
                                    │  (sensor_data)  │
                                    └────────▲────────┘
                                             │ Store
                                             │
┌──────────┐      MQTT       ┌───────────────┴───────────────┐
│Equipment │ ──────────────► │         AWS IoT Core          │
│ (EQ-001) │   raw/{serial}  │                               │
└──────────┘                 │  ┌─────────────────────────┐  │
                             │  │ IoT Rule:               │  │
                             │  │ 1. Lookup company_id    │  │
                             │  │ 2. Store to DynamoDB    │  │
                             │  │ 3. Republish to secure  │  │
                             │  │    topic                │  │
                             │  └─────────────────────────┘  │
                             └───────────────┬───────────────┘
                                             │ Republish
                                             │ companies/{company_id}/{serial}
                                             ▼
┌──────────────────────────────────────────────────────────────┐
│                        Frontend (React)                       │
│  ┌────────────┐  ┌─────────────────┐  ┌───────────────────┐  │
│  │   Login    │  │ Equipment Select│  │ Real-time Display │  │
│  │ (Cognito)  │  │ (Company-scoped)│  │ + History Charts  │  │
│  └────────────┘  └─────────────────┘  └───────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                             │
                             │ REST API (for history)
                             ▼
                    ┌─────────────────┐
                    │  Lambda         │
                    │  (history API)  │
                    └─────────────────┘
```

## Multi-Tenancy Security Model

This project implements the **Republish Pattern** for secure multi-tenant data isolation:

1. **Equipment** publishes to a generic topic: `raw/{serial_number}`
2. **IoT Core Rule** looks up the serial number in `equipment_registry` to find the `company_id`
3. **IoT Core** republishes to a secure topic: `companies/{company_id}/{serial_number}`
4. **Users** can only subscribe to their company's topics (enforced by IAM policy using Cognito attributes)

This ensures that even if a user attempts to modify frontend code to access another company's data, AWS IAM will reject the request.

## Data Model

### Hierarchy
```
Company → Equipment → Sensor Readings
```

### Equipment Registry Table
Maps equipment serial numbers to companies.

| serial_number | company_id | name (optional) |
|---------------|------------|-----------------|
| EQ-001 | comp-A | Warehouse Unit 1 |
| EQ-002 | comp-A | Warehouse Unit 2 |
| EQ-003 | comp-B | Factory Floor 1 |

### Sensor Data Table
Stores historical sensor readings.

| serial_number (PK) | timestamp (SK) | temp | humidity | co2 |
|--------------------|----------------|------|----------|-----|
| EQ-001 | 1707900000 | 72 | 45 | 400 |

### Sensor Payload Format
Equipment sends JSON payloads with the following structure:

```json
{
  "serial_number": "EQ-001",
  "timestamp": 1707900000,
  "temp": 72,
  "humidity": 45,
  "co2": 400
}
```

The system accepts any JSON payload, but the demo uses these 5 fields.

## Demo Setup

### Companies and Equipment

| Company | Equipment IDs |
|---------|---------------|
| comp-A | EQ-001, EQ-002 |
| comp-B | EQ-003, EQ-004 |
| comp-C | EQ-005 |

**Total:** 3 companies, 5 equipment units

## Project Structure

```
real-time-iot-monitoring/
│
├── README.md
├── .gitignore
│
├── infra/                      # Terraform (Infrastructure as Code)
│   ├── main.tf                 # Core resources (DynamoDB, IoT Rules, Lambda, Cognito)
│   ├── variables.tf            # Configuration (region, project name)
│   ├── outputs.tf              # Outputs (API URL, Cognito IDs, IoT endpoint)
│   └── provider.tf             # AWS provider setup
│
├── backend/                    # Lambda Functions
│   └── history_service/
│       └── index.py            # Historical data API (company-scoped queries)
│
├── frontend/                   # React Application
│   ├── public/
│   ├── src/
│   │   ├── components/         # UI components (EquipmentSelector, SensorChart, etc.)
│   │   ├── services/           # API client, MQTT connection
│   │   ├── App.js
│   │   └── config.js           # AWS configuration (from Terraform outputs)
│   ├── package.json
│   └── vite.config.js
│
└── simulators/                 # Testing Tools
    ├── device_cert/            # IoT certificates (gitignored)
    │   ├── device.pem.crt
    │   ├── private.pem.key
    │   └── AmazonRootCA1.pem
    ├── fake_equipment.py       # Simulates equipment sending MQTT data
    └── seed_registry.py        # Seeds equipment_registry table with demo data
```

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Node.js](https://nodejs.org/) >= 18
- [Python](https://www.python.org/) >= 3.9
- An AWS account (Free Tier eligible)

## Deployment

### 1. Deploy Infrastructure

```bash
cd infra
terraform init
terraform plan
terraform apply
```

Save the outputs - you'll need them for the frontend configuration.

### 2. Seed Demo Data

```bash
cd simulators
pip install boto3
python seed_registry.py
```

This populates the `equipment_registry` table with the 5 demo equipment units.

### 3. Create Test Users

Manually create users in AWS Cognito Console (or use AWS CLI):

```bash
# Example: Create a user for comp-A
aws cognito-idp admin-create-user \
  --user-pool-id <USER_POOL_ID> \
  --username demo-user-a \
  --user-attributes Name=custom:company_id,Value=comp-A
```

### 4. Configure Frontend

Copy Terraform outputs to `frontend/src/config.js`:

```javascript
export const awsConfig = {
  region: "ca-central-1",
  iotEndpoint: "wss://xxxxx.iot.ca-central-1.amazonaws.com/mqtt",
  apiHistoryUrl: "https://xxxxx.lambda-url.ca-central-1.on.aws/",
  cognitoUserPoolId: "ca-central-1_xxxxx",
  cognitoClientId: "xxxxx",
  cognitoIdentityPoolId: "ca-central-1:xxxxx"
};
```

### 5. Run Frontend

```bash
cd frontend
npm install
npm run dev
```

### 6. Run Simulator

```bash
cd simulators
pip install AWSIoTPythonSDK
python fake_equipment.py
```

This simulates all 5 equipment units sending sensor data every 5 seconds.

## MQTT Topics

| Topic Pattern | Purpose | Example |
|---------------|---------|---------|
| `raw/{serial}` | Equipment publishes here | `raw/EQ-001` |
| `companies/{company_id}/{serial}` | Secure topic for frontend | `companies/comp-A/EQ-001` |

## AWS Free Tier Usage

| Service | Free Tier Limit | Usage in This Project |
|---------|-----------------|----------------------|
| DynamoDB | 25GB storage, 25 RCU/WCU | Well under limits |
| IoT Core | 500k messages/month (12 months) | Demo uses minimal messages |
| Cognito | 50,000 MAU | Always free |
| Lambda | 1M requests/month | Always free |
| Amplify Hosting | 15GB bandwidth/month (12 months) | Minimal for demo |

## Frontend Features (MVP)

1. **Login** - Cognito authentication
2. **Equipment Selector** - Dropdown list of equipment belonging to user's company
3. **Real-Time Display** - Live sensor readings for selected equipment
4. **Historical Charts** - Query and visualize past sensor data for selected equipment

## Security Considerations

- **IAM Policy Variables**: Users can only subscribe to topics matching their `company_id` attribute
- **Equipment Registry Lookup**: IoT Rules verify equipment exists before republishing
- **Company-Scoped History API**: Lambda validates user's company_id before returning data
- **No Hardcoded Secrets**: Cognito handles authentication; no API keys in frontend code

## Future Enhancements

- [ ] Admin dashboard for managing equipment and companies
- [ ] Alerting/thresholds (e.g., notify when temp > 80)
- [ ] Data export (CSV, JSON)
- [ ] Multiple sensor types per equipment
- [ ] Equipment status indicators (online/offline)
- [ ] User management UI

## Live Demo

**URL:** https://deufddidqolmw.cloudfront.net/

**Account:** demo@example.com

