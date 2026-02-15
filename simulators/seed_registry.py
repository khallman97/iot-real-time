"""
Seed Script - Populates the equipment_registry table with demo data.

Run this after deploying Terraform infrastructure:
    cd simulators
    pip install boto3
    python seed_registry.py
"""

import boto3
import os

# Configuration - update these if you changed the defaults
AWS_REGION = os.environ.get('AWS_REGION', 'ca-central-1')
TABLE_NAME = os.environ.get('EQUIPMENT_REGISTRY_TABLE', 'iot-monitoring-equipment-registry')

# Demo data: 5 equipment across 3 companies
DEMO_EQUIPMENT = [
    {
        'serial_number': 'EQ-001',
        'company_id': 'comp-A',
        'name': 'Warehouse Unit 1',
        'location': 'Building A, Floor 1'
    },
    {
        'serial_number': 'EQ-002',
        'company_id': 'comp-A',
        'name': 'Warehouse Unit 2',
        'location': 'Building A, Floor 2'
    },
    {
        'serial_number': 'EQ-003',
        'company_id': 'comp-B',
        'name': 'Factory Floor 1',
        'location': 'Main Factory'
    },
    {
        'serial_number': 'EQ-004',
        'company_id': 'comp-B',
        'name': 'Factory Floor 2',
        'location': 'Secondary Factory'
    },
    {
        'serial_number': 'EQ-005',
        'company_id': 'comp-C',
        'name': 'Office Monitor',
        'location': 'Headquarters'
    }
]


def seed_equipment_registry():
    """Insert demo equipment into DynamoDB."""
    dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
    table = dynamodb.Table(TABLE_NAME)

    print(f"Seeding {TABLE_NAME} in {AWS_REGION}...")
    print("-" * 50)

    for equipment in DEMO_EQUIPMENT:
        try:
            table.put_item(Item=equipment)
            print(f"  Added: {equipment['serial_number']} -> {equipment['company_id']} ({equipment['name']})")
        except Exception as e:
            print(f"  Error adding {equipment['serial_number']}: {e}")

    print("-" * 50)
    print(f"Done! Added {len(DEMO_EQUIPMENT)} equipment entries.")
    print()
    print("Demo setup:")
    print("  comp-A: EQ-001, EQ-002")
    print("  comp-B: EQ-003, EQ-004")
    print("  comp-C: EQ-005")


if __name__ == '__main__':
    seed_equipment_registry()
