"""
History API Lambda Function

Provides company-scoped access to historical sensor data.
Users can only query equipment belonging to their company.
"""

import json
import os
import boto3
from decimal import Decimal
from boto3.dynamodb.conditions import Key

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
sensor_data_table = dynamodb.Table(os.environ['SENSOR_DATA_TABLE'])
equipment_registry_table = dynamodb.Table(os.environ['EQUIPMENT_REGISTRY_TABLE'])


class DecimalEncoder(json.JSONEncoder):
    """Handle Decimal types from DynamoDB."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def get_company_id_from_token(event):
    """Extract company_id from the Cognito JWT token claims."""
    try:
        claims = event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {})
        return claims.get('custom:company_id')
    except Exception:
        return None


def verify_equipment_ownership(serial_number, company_id):
    """Verify that the equipment belongs to the specified company."""
    try:
        response = equipment_registry_table.get_item(
            Key={'serial_number': serial_number}
        )
        item = response.get('Item')
        if item and item.get('company_id') == company_id:
            return True
        return False
    except Exception:
        return False


def get_company_equipment(company_id):
    """Get all equipment belonging to a company."""
    try:
        response = equipment_registry_table.query(
            IndexName='company-index',
            KeyConditionExpression=Key('company_id').eq(company_id)
        )
        return response.get('Items', [])
    except Exception as e:
        print(f"Error querying equipment: {e}")
        return []


def get_sensor_history(serial_number, start_time=None, end_time=None, limit=100):
    """Get historical sensor data for a specific equipment."""
    try:
        key_condition = Key('serial_number').eq(serial_number)

        # Add time range filter if provided
        if start_time and end_time:
            key_condition = key_condition & Key('timestamp').between(
                int(start_time), int(end_time)
            )
        elif start_time:
            key_condition = key_condition & Key('timestamp').gte(int(start_time))
        elif end_time:
            key_condition = key_condition & Key('timestamp').lte(int(end_time))

        response = sensor_data_table.query(
            KeyConditionExpression=key_condition,
            ScanIndexForward=False,  # Most recent first
            Limit=limit
        )
        return response.get('Items', [])
    except Exception as e:
        print(f"Error querying sensor data: {e}")
        return []


def handler(event, context):
    """Main Lambda handler."""
    print(f"Event: {json.dumps(event)}")

    # Parse request
    http_method = event.get('requestContext', {}).get('http', {}).get('method', 'GET')
    path = event.get('rawPath', '/')
    query_params = event.get('queryStringParameters') or {}

    # Route handling
    try:
        # Health check (no auth required)
        if path == '/health':
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'status': 'healthy'})
            }

        # Get company_id from token (required for other routes)
        company_id = get_company_id_from_token(event)

        if not company_id:
            return {
                'statusCode': 401,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Unauthorized: company_id not found in token'})
            }

        # GET /equipment - List equipment for company
        if path == '/equipment' and http_method == 'GET':
            equipment = get_company_equipment(company_id)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'company_id': company_id,
                    'equipment': equipment
                }, cls=DecimalEncoder)
            }

        # GET /history?serial_number=XXX&start_time=XXX&end_time=XXX&limit=XXX
        elif path == '/history' and http_method == 'GET':
            serial_number = query_params.get('serial_number')

            if not serial_number:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 'serial_number is required'})
                }

            # Verify ownership
            if not verify_equipment_ownership(serial_number, company_id):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 'Access denied: equipment not found or not owned by your company'})
                }

            # Get history
            start_time = query_params.get('start_time')
            end_time = query_params.get('end_time')
            limit = int(query_params.get('limit', 100))

            history = get_sensor_history(serial_number, start_time, end_time, limit)

            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'serial_number': serial_number,
                    'company_id': company_id,
                    'count': len(history),
                    'data': history
                }, cls=DecimalEncoder)
            }

        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Not found'})
            }

    except Exception as e:
        print(f"Error: {e}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
