"""
Helper script to fetch Local Key and Local IP for Tuya Device d72c4dd24f074a08fdwvz4.
"""

import sys
import tinytuya

def fetch_details(api_key, api_secret, device_id="d72c4dd24f074a08fdwvz4", region="in"):
    print(f"Connecting to Tuya Cloud API ({region.upper()}) for Device {device_id}...")
    cloud = tinytuya.Cloud(
        apiEndpoint=f"https://openapi.tuya{region}.com",
        apiKey=api_key,
        apiSecret=api_secret
    )
    
    # Get device details including local_key
    devices = cloud.getdevices()
    print("\nDevices found under project:")
    found = False
    for dev in devices:
        dev_id = dev.get("id")
        name = dev.get("name")
        key = dev.get("key")
        ip = dev.get("ip")
        print(f"  - [{name}] ID: {dev_id} | Local Key: {key} | IP: {ip}")
        if dev_id == device_id:
            found = True
            print("\n" + "=" * 55)
            print("MATCH FOUND!")
            print(f"  Device ID : {dev_id}")
            print(f"  Local Key : {key}")
            print(f"  Local IP  : {ip}")
            print("=" * 55)
            
    if not found:
        print(f"\nNote: If device {device_id} was not returned, check if region is 'in' (India), 'us', or 'eu'.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python scripts/fetch_tuya_local_key.py <TUYA_ACCESS_ID> <TUYA_ACCESS_SECRET> [REGION]")
        print("Example: python scripts/fetch_tuya_local_key.py your_client_id your_client_secret in")
    else:
        region = sys.argv[3] if len(sys.argv) > 3 else "in"
        fetch_details(sys.argv[1], sys.argv[2], region=region)
