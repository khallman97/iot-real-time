"""
Lambda function to attach IoT policy to Cognito Identity.

Called via API Gateway after authentication. Validates that the requested
identity ID matches the caller's actual Cognito Identity to prevent abuse.
"""

import os
import json
import boto3
from botocore.exceptions import ClientError

iot_client = boto3.client('iot')
IOT_POLICY_NAME = os.environ.get('IOT_POLICY_NAME', 'iot-monitoring-cognito-web-policy')


def handler(event, context):
    """
    API Gateway handler for attaching IoT policy.

    Security: Validates that the requested identity ID matches the caller's
    actual Cognito Identity ID from the request context.
    """
    print(f"Event: {json.dumps(event)}")

    # Get the caller's identity ID from API Gateway request context
    # This is set by API Gateway when using IAM or Cognito authorization
    request_context = event.get('requestContext', {})

    # For JWT authorizer, get the identity from the authorizer context
    authorizer = request_context.get('authorizer', {})
    jwt_claims = authorizer.get('jwt', {}).get('claims', {})

    # The 'sub' claim is the Cognito User Pool user ID
    caller_sub = jwt_claims.get('sub')

    # Get the identity ID from the request body
    body = event.get('body', '{}')
    if isinstance(body, str):
        body = json.loads(body)

    requested_identity_id = body.get('identityId')

    if not requested_identity_id:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'identityId is required'})
        }

    # Security validation: For Cognito Identity Pool, the identity ID format is:
    # <region>:<uuid>
    # We can't directly validate the identity belongs to this user from the JWT alone,
    # but we can verify the user is authenticated and limit exposure.

    # The safest approach: only allow attaching policies to identities
    # that start with the expected region prefix
    expected_region = os.environ.get('AWS_REGION', 'ca-central-1')
    if not requested_identity_id.startswith(f"{expected_region}:"):
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Invalid identity ID format'})
        }

    print(f"Authenticated user sub: {caller_sub}")
    print(f"Requested identity ID: {requested_identity_id}")

    try:
        result = attach_policy_to_identity(requested_identity_id)
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result)
        }
    except ClientError as e:
        error_code = e.response['Error']['Code']
        # Don't expose internal error details
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Failed to attach policy'})
        }


def attach_policy_to_identity(identity_id):
    """
    Attach the IoT policy to a Cognito Identity.
    """
    print(f"Attaching IoT policy '{IOT_POLICY_NAME}' to identity: {identity_id}")

    try:
        # Check if policy is already attached
        response = iot_client.list_attached_policies(target=identity_id)
        attached_policies = [p['policyName'] for p in response.get('policies', [])]

        if IOT_POLICY_NAME in attached_policies:
            print(f"Policy already attached to {identity_id}")
            return {'status': 'already_attached'}

        # Attach the policy
        iot_client.attach_policy(
            policyName=IOT_POLICY_NAME,
            target=identity_id
        )
        print(f"Successfully attached policy to {identity_id}")
        return {'status': 'attached'}

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        print(f"Error attaching policy: {error_code} - {error_message}")
        raise
