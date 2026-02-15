// AWS Configuration
// Update these values after running `terraform apply` in /infra


export const awsConfig = {
  region: "ca-central-1",
  iotEndpoint: "wss://a9ro0t65wkcmk-ats.iot.ca-central-1.amazonaws.com/mqtt",
  apiUrl: "https://hhejbzv708.execute-api.ca-central-1.amazonaws.com",
  cognitoUserPoolId: "ca-central-1_d3iJglKP2",
  cognitoClientId: "7es8qu40r6sfu21q4sf58r3c1v",
  cognitoIdentityPoolId: "ca-central-1:a7992ed4-88d5-4038-98db-d4aa30af5010"
};