"""
Fake Equipment Simulator - Sends MQTT sensor data to AWS IoT Core.

This script simulates 5 equipment units sending sensor readings every 5 seconds.

Prerequisites:
    1. Deploy Terraform infrastructure
    2. Create IoT certificates:
       aws iot create-keys-and-certificate --set-as-active \
         --certificate-pem-outfile device_cert/device.pem.crt \
         --private-key-outfile device_cert/private.pem.key

    3. Attach the policy to the certificate:
       aws iot attach-policy --policy-name iot-monitoring-simulator-policy \
         --target <certificate-arn>

    4. Download Amazon Root CA:
       curl -o device_cert/AmazonRootCA1.pem \
         https://www.amazontrust.com/repository/AmazonRootCA1.pem

    5. Install dependencies:
       pip install AWSIoTPythonSDK

    6. Run:
       python fake_equipment.py

Usage:
    python fake_equipment.py [--endpoint YOUR_IOT_ENDPOINT] [--interval 5]
"""

import json
import time
import random
import argparse
import os
from datetime import datetime

try:
    from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient
except ImportError:
    print("Error: AWSIoTPythonSDK not installed.")
    print("Run: pip install AWSIoTPythonSDK")
    exit(1)


# Configuration
DEFAULT_ENDPOINT = os.environ.get('IOT_ENDPOINT', 'YOUR_IOT_ENDPOINT_HERE')
CERT_DIR = os.path.join(os.path.dirname(__file__), 'device_cert')
ROOT_CA = os.path.join(CERT_DIR, 'AmazonRootCA1.pem')
CERT_FILE = os.path.join(CERT_DIR, 'device.pem.crt')
KEY_FILE = os.path.join(CERT_DIR, 'private.pem.key')

# Equipment to simulate
EQUIPMENT = ['EQ-001', 'EQ-002', 'EQ-003', 'EQ-004', 'EQ-005']


def generate_sensor_data(serial_number):
    """Generate realistic sensor readings."""
    return {
        'serial_number': serial_number,
        'timestamp': int(time.time()),
        'temp': round(random.uniform(18.0, 28.0), 1),        # Temperature in Celsius
        'humidity': round(random.uniform(30.0, 70.0), 1),    # Humidity percentage
        'co2': random.randint(350, 600)                       # CO2 in ppm
    }


def verify_certificates():
    """Check if certificate files exist."""
    missing = []
    for f in [ROOT_CA, CERT_FILE, KEY_FILE]:
        if not os.path.exists(f):
            missing.append(f)

    if missing:
        print("Missing certificate files:")
        for f in missing:
            print(f"  - {f}")
        print()
        print("Please follow the setup instructions in the script header.")
        return False
    return True


def create_mqtt_client(endpoint, client_id):
    """Create and configure MQTT client."""
    client = AWSIoTMQTTClient(client_id)
    client.configureEndpoint(endpoint, 8883)
    client.configureCredentials(ROOT_CA, KEY_FILE, CERT_FILE)

    # Configure connection settings
    client.configureAutoReconnectBackoffTime(1, 32, 20)
    client.configureOfflinePublishQueueing(-1)
    client.configureDrainingFrequency(2)
    client.configureConnectDisconnectTimeout(10)
    client.configureMQTTOperationTimeout(5)

    return client


def main():
    parser = argparse.ArgumentParser(description='Simulate IoT equipment sending sensor data')
    parser.add_argument('--endpoint', default=DEFAULT_ENDPOINT,
                        help='AWS IoT Core endpoint')
    parser.add_argument('--interval', type=int, default=5,
                        help='Seconds between sensor readings')
    parser.add_argument('--equipment', nargs='+', default=EQUIPMENT,
                        help='Equipment serial numbers to simulate')
    args = parser.parse_args()

    if args.endpoint == 'YOUR_IOT_ENDPOINT_HERE':
        print("Error: IoT endpoint not configured.")
        print("Set IOT_ENDPOINT environment variable or use --endpoint flag.")
        print()
        print("Get your endpoint with: aws iot describe-endpoint --endpoint-type iot:Data-ATS")
        return

    if not verify_certificates():
        return

    print("=" * 60)
    print("IoT Equipment Simulator")
    print("=" * 60)
    print(f"Endpoint: {args.endpoint}")
    print(f"Equipment: {', '.join(args.equipment)}")
    print(f"Interval: {args.interval} seconds")
    print("=" * 60)
    print()

    # Create MQTT client
    client_id = f"simulator-{int(time.time())}"
    client = create_mqtt_client(args.endpoint, client_id)

    print("Connecting to AWS IoT Core...")
    try:
        client.connect()
        print("Connected!")
        print()
    except Exception as e:
        print(f"Connection failed: {e}")
        return

    print("Sending sensor data (Ctrl+C to stop)...")
    print("-" * 60)

    try:
        while True:
            for serial_number in args.equipment:
                # Generate sensor data
                data = generate_sensor_data(serial_number)
                topic = f"raw/{serial_number}"

                # Publish
                payload = json.dumps(data)
                client.publish(topic, payload, 1)

                timestamp = datetime.now().strftime('%H:%M:%S')
                print(f"[{timestamp}] {topic}: temp={data['temp']}C, humidity={data['humidity']}%, co2={data['co2']}ppm")

            print("-" * 60)
            time.sleep(args.interval)

    except KeyboardInterrupt:
        print()
        print("Stopping simulator...")

    finally:
        client.disconnect()
        print("Disconnected.")


if __name__ == '__main__':
    main()
