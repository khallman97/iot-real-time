# Frontend

React dashboard for IoT monitoring.

## Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- Terraform infrastructure deployed (see `/infra`)

## Local Development

### 1. Install dependencies

```bash
npm install
```

### 2. Configure AWS settings

After running `terraform apply`, copy the outputs to `src/config.js`:

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

Or copy the `frontend_config` output directly from Terraform.

### 3. Run development server

```bash
npm run dev
```

Open http://localhost:5173

## Build for Production

```bash
npm run build
```

Output is in the `dist/` folder.

## Deploy to AWS Amplify

### Option 1: Connect to GitHub (Recommended)

1. Push your code to GitHub
2. Go to AWS Amplify Console
3. Click "New app" > "Host web app"
4. Connect your GitHub repo
5. Select the branch and set build settings:
   - Build command: `cd frontend && npm ci && npm run build`
   - Output directory: `frontend/dist`
6. Add environment variables (optional - or hardcode in config.js)
7. Deploy

Amplify will auto-deploy on every push.

### Option 2: Manual Deploy

```bash
# Build
npm run build

# Install Amplify CLI (if not installed)
npm install -g @aws-amplify/cli

# Deploy
amplify publish
```

### Option 3: S3 + CloudFront

```bash
# Build
npm run build

# Sync to S3
aws s3 sync dist/ s3://your-bucket-name --delete

# Invalidate CloudFront cache (if using)
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

## Project Structure

```
src/
├── main.jsx              # Entry point
├── App.jsx               # Main app component
├── App.css               # Styles
├── config.js             # AWS configuration
├── components/
│   ├── Login.jsx         # Login form
│   ├── EquipmentSelector.jsx
│   ├── RealtimeDisplay.jsx
│   └── HistoryChart.jsx
└── services/
    ├── auth.js           # Cognito authentication
    ├── mqtt.js           # IoT Core MQTT
    └── api.js            # Lambda API client
```

## Troubleshooting

### "Not authenticated" error
- Ensure Cognito User Pool and Identity Pool IDs are correct
- Check that the user has `custom:company_id` attribute set

### MQTT not connecting
- Verify IoT endpoint is correct
- Check IAM policies allow `iot:Connect`, `iot:Subscribe`, `iot:Receive`
- Ensure Identity Pool role mapping is configured

### No equipment showing
- Run the seed script: `python simulators/seed_registry.py`
- Verify the user's `company_id` matches equipment in the registry
