#!/usr/bin/env python3
"""
Mock Historical Sensor Data Loader

Generates realistic sensor data for testing the historical dashboard UI.
Bulk-inserts data to BigQuery, then uses the ingestData endpoint for the
final timestamp to ensure Firestore state is synced.

Usage:
    python load_mock_data.py --start-date "2026-01-10T00:00:00Z" --end-date "2026-02-10T00:00:00Z" --interval-minutes 15 --correlation-factor 0.7

Environment:
    GOOGLE_APPLICATION_CREDENTIALS: Path to GCP service account JSON
"""

import argparse
import json
import math
import random
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Tuple

import pytz
import requests
from google.cloud import bigquery


# Default configuration (matches Arduino deployment)
DEFAULT_ORG_ID = "h5MpqlFvAMAXEZLy40li"
DEFAULT_SITE_ID = "vdnFM3S1fBd1enusXSpa"
DEFAULT_ZONE_IDS = ["WEfQvcglxxGmoGelKRgS", "QOqNlovWoN5lZNmBsXcF"]  # Can specify multiple zones
DEFAULT_PROJECT_ID = "agrivoltaics-flutter-firebase"
DEFAULT_INGEST_ENDPOINT = "https://us-central1-agrivoltaics-flutter-firebase.cloudfunctions.net/ingestSensorData"

# BigQuery schema
DATASET_ID = "sensor_data"
TABLE_ID = "readings"

# Sensor configurations template (sensor_type -> {model, name, fields})
# Actual sensor IDs will be generated per zone
SENSOR_TEMPLATES = {
    "weather": {
        "model": "DHT22",
        "name": "Weather Sensor",
        "fields": {
            "temperature": {"unit": "°F", "min": 50, "max": 85, "diurnal": True},
            "humidity": {"unit": "%", "min": 40, "max": 80, "diurnal": False},
        },
    },
    "light": {
        "model": "VEML7700",
        "name": "Light Sensor",
        "fields": {
            "light": {"unit": "lux", "min": 100, "max": 80000, "diurnal": True},
        },
    },
    "soil": {
        "model": "DFRobot-Soil",
        "name": "Soil Sensor",
        "fields": {
            "soilMoisture": {"unit": "%", "min": 30, "max": 70, "diurnal": False},
            "soilTemperature": {"unit": "°F", "min": 55, "max": 75, "diurnal": True},
            "soilEC": {"unit": "μS/cm", "min": 800, "max": 2000, "diurnal": False},
        },
    },
    "co2": {
        "model": "SGP30",
        "name": "CO2 Sensor",
        "fields": {
            "co2": {"unit": "ppm", "min": 400, "max": 800, "diurnal": False},
            "tvoc": {"unit": "ppm", "min": 0, "max": 150, "diurnal": False},
        },
    },
}

# Default sensor IDs for first zone (Zone WEfQvcglxxGmoGelKRgS)
DEFAULT_ZONE_SENSORS = {
    "WEfQvcglxxGmoGelKRgS": {
        "weather": "lf5uODvVmWtLnM1d3Jxm",
        "light": "lIEs7hKlOX2ZCbjlOJZ6",
        "soil": "U5kymcFPBhhnsVFO0YeO",
        "co2": "LH5FoEnrj014cxNxMopa",
    },
    "QOqNlovWoN5lZNmBsXcF": {
        "weather": "PEB0rwJDdEtiP4jGPRYw",
        "light": "4pqIOJ9eqSjZbLfy99Nn",
        "soil": "IG1BirAtaKND5tfnj5zD",
        "co2": "R3N69xwm3mchaUsgUMjO",
    }
}


def get_sensors_for_zone(zone_id: str) -> Dict[str, dict]:
    """
    Get sensor configurations for a specific zone.
    Returns dict of {sensorId: sensor_config} for the zone.
    
    If zone has custom sensor IDs defined, uses those.
    Otherwise generates sensor IDs as: {sensor_type}_{last_8_chars_of_zone_id}
    """
    sensors = {}
    
    for sensor_type, template in SENSOR_TEMPLATES.items():
        # Check if we have a predefined sensor ID for this zone
        if zone_id in DEFAULT_ZONE_SENSORS and sensor_type in DEFAULT_ZONE_SENSORS[zone_id]:
            sensor_id = DEFAULT_ZONE_SENSORS[zone_id][sensor_type]
        else:
            # Generate a unique sensor ID for this zone
            zone_suffix = zone_id[-8:] if len(zone_id) >= 8 else zone_id
            sensor_id = f"{sensor_type}_{zone_suffix}"
        
        sensors[sensor_id] = template
    
    return sensors


class SensorDataGenerator:
    """Generates realistic sensor data with optional point-to-point correlation."""

    def __init__(self, correlation_factor: float = 0.7):
        """
        Initialize generator.

        Args:
            correlation_factor: 0.0-1.0, controls smoothness between points.
                               0.0 = pure random, 1.0 = maximum correlation
        """
        self.correlation_factor = max(0.0, min(1.0, correlation_factor))
        self.previous_values: Dict[Tuple[str, str], float] = {}

    def generate_value(
        self,
        sensor_id: str,
        field_name: str,
        field_config: dict,
        timestamp: datetime,
    ) -> float:
        """Generate a single sensor value."""
        min_val = field_config["min"]
        max_val = field_config["max"]
        diurnal = field_config.get("diurnal", False)

        # Base random value
        base_random = random.uniform(min_val, max_val)

        # Apply diurnal pattern if configured
        if diurnal:
            hour = timestamp.hour
            # Sine wave: peak around 14:00, trough around 2:00
            diurnal_factor = math.sin((hour - 2) * math.pi / 12)
            # Scale factor between -0.3 and +0.3 of range
            range_size = max_val - min_val
            diurnal_adjustment = diurnal_factor * range_size * 0.3
            base_random += diurnal_adjustment
            base_random = max(min_val, min(max_val, base_random))

        # Apply correlation if previous value exists
        key = (sensor_id, field_name)
        if self.correlation_factor > 0 and key in self.previous_values:
            prev_value = self.previous_values[key]
            # Blend previous value with new random value
            value = (prev_value * self.correlation_factor +
                    base_random * (1 - self.correlation_factor))
            # Add small random walk
            walk_size = (max_val - min_val) * 0.05
            value += random.uniform(-walk_size, walk_size)
            # Clamp to range
            value = max(min_val, min(max_val, value))
        else:
            value = base_random

        # Store for next iteration
        self.previous_values[key] = value

        # Round based on field type
        if field_name in ["soilMoisture", "soilEC", "co2", "tvoc"]:
            return round(value)
        else:
            return round(value, 1)


def generate_timestamps(
    start_date: datetime,
    end_date: datetime,
    interval_minutes: int,
) -> List[datetime]:
    """Generate list of timestamps from start to end at given interval."""
    timestamps = []
    current = start_date
    while current <= end_date:
        timestamps.append(current)
        current += timedelta(minutes=interval_minutes)
    return timestamps


def generate_bigquery_rows(
    timestamps: List[datetime],
    org_id: str,
    site_id: str,
    zone_ids: List[str],
    generator: SensorDataGenerator,
) -> List[dict]:
    """Generate BigQuery row dicts for all timestamps except the last."""
    rows = []

    # Process all but the last timestamp
    for timestamp in timestamps[:-1]:
        for zone_id in zone_ids:
            # Get zone-specific sensors
            zone_sensors = get_sensors_for_zone(zone_id)
            
            for sensor_id, sensor_config in zone_sensors.items():
                for field_name, field_config in sensor_config["fields"].items():
                    value = generator.generate_value(
                        sensor_id, field_name, field_config, timestamp
                    )

                    row = {
                        "timestamp": timestamp.isoformat(),
                        "organizationId": org_id,
                        "siteId": site_id,
                        "zoneId": zone_id,
                        "sensorId": sensor_id,
                        "sensorModel": sensor_config["model"],
                        "sensorName": sensor_config["name"],
                        "field": field_name,
                        "value": value,
                        "unit": field_config["unit"],
                        "primarySensor": True,  # Simplified for mock data
                    }
                    rows.append(row)

    return rows


def generate_ingest_payload(
    timestamp: datetime,
    org_id: str,
    site_id: str,
    zone_id: str,
    generator: SensorDataGenerator,
) -> dict:
    """Generate payload for the ingestData endpoint (last timestamp only)."""
    sensors = []
    
    # Get zone-specific sensors
    zone_sensors = get_sensors_for_zone(zone_id)

    for sensor_id, sensor_config in zone_sensors.items():
        readings = {}
        for field_name, field_config in sensor_config["fields"].items():
            value = generator.generate_value(
                sensor_id, field_name, field_config, timestamp
            )
            readings[field_name] = {
                "value": value,
                "unit": field_config["unit"],
            }

        sensors.append({
            "sensorId": sensor_id,
            "timestamp": int(timestamp.timestamp()),
            "readings": readings,
        })

    return {
        "organizationId": org_id,
        "siteId": site_id,
        "zoneId": zone_id,
        "sensors": sensors,
    }


def bulk_insert_to_bigquery(
    rows: List[dict],
    project_id: str,
    batch_size: int = 10000,
) -> Tuple[int, int]:
    """
    Bulk insert rows to BigQuery.

    Args:
        rows: List of row dicts
        project_id: GCP project ID
        batch_size: Max rows per insert batch

    Returns:
        Tuple of (successful_rows, failed_rows)
    """
    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{DATASET_ID}.{TABLE_ID}"

    total_success = 0
    total_failed = 0

    # Process in batches
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        errors = client.insert_rows_json(table_ref, batch)

        if errors:
            print(f"  ⚠️  Batch {i//batch_size + 1}: {len(errors)} errors")
            total_failed += len(errors)
            for error in errors[:5]:  # Show first 5 errors
                print(f"      {error}")
        else:
            total_success += len(batch)

    return total_success, total_failed


def post_to_ingest_endpoint(payload: dict, endpoint: str) -> bool:
    """
    POST the final data point to the ingestData endpoint.

    Args:
        payload: Dict matching ingestSensorData format
        endpoint: Cloud Function URL

    Returns:
        True if successful, False otherwise
    """
    try:
        response = requests.post(endpoint, json=payload, timeout=30)
        response.raise_for_status()

        result = response.json()
        if result.get("success"):
            sensors_processed = result.get("sensorsProcessed", 0)
            print(f"  ✓ Firestore updated: {sensors_processed} sensors processed")
            return True
        else:
            print(f"  ✗ Firestore update failed: {result.get('message', 'Unknown error')}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"  ✗ HTTP request failed: {e}")
        return False
    except json.JSONDecodeError:
        print(f"  ✗ Invalid JSON response")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate mock historical sensor data for testing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    parser.add_argument(
        "--start-date",
        required=True,
        help="Start date in ISO 8601 format (e.g., '2026-02-01T00:00:00Z')",
    )
    parser.add_argument(
        "--end-date",
        required=True,
        help="End date in ISO 8601 format (e.g., '2026-02-10T00:00:00Z')",
    )
    parser.add_argument(
        "--interval-minutes",
        type=int,
        default=15,
        help="Interval between data points in minutes (default: 15)",
    )
    parser.add_argument(
        "--correlation-factor",
        type=float,
        default=0.7,
        help="Point-to-point correlation (0.0=random, 1.0=smooth) (default: 0.7)",
    )
    parser.add_argument(
        "--org-id",
        default=DEFAULT_ORG_ID,
        help=f"Organization ID (default: {DEFAULT_ORG_ID})",
    )
    parser.add_argument(
        "--site-id",
        default=DEFAULT_SITE_ID,
        help=f"Site ID (default: {DEFAULT_SITE_ID})",
    )
    parser.add_argument(
        "--zone-ids",
        nargs="+",
        default=DEFAULT_ZONE_IDS,
        help=f"Zone ID(s) - space separated for multiple zones (default: {DEFAULT_ZONE_IDS[0]})",
    )
    parser.add_argument(
        "--project-id",
        default=DEFAULT_PROJECT_ID,
        help=f"GCP project ID (default: {DEFAULT_PROJECT_ID})",
    )
    parser.add_argument(
        "--ingest-endpoint",
        default=DEFAULT_INGEST_ENDPOINT,
        help=f"ingestData endpoint URL (default: {DEFAULT_INGEST_ENDPOINT})",
    )
    parser.add_argument(
        "--skip-firestore",
        action="store_true",
        help="Skip posting last data point to ingestData endpoint",
    )

    args = parser.parse_args()

    # Parse dates
    try:
        start_date = datetime.fromisoformat(args.start_date.replace("Z", "+00:00"))
        end_date = datetime.fromisoformat(args.end_date.replace("Z", "+00:00"))
    except ValueError as e:
        print(f"Error parsing dates: {e}")
        sys.exit(1)

    if start_date >= end_date:
        print("Error: start-date must be before end-date")
        sys.exit(1)

    # Ensure dates are UTC
    if start_date.tzinfo is None:
        start_date = pytz.utc.localize(start_date)
    if end_date.tzinfo is None:
        end_date = pytz.utc.localize(end_date)

    print("=" * 70)
    print("Mock Historical Sensor Data Loader")
    print("=" * 70)
    print(f"Date range:      {start_date} to {end_date}")
    print(f"Interval:        {args.interval_minutes} minutes")
    print(f"Correlation:     {args.correlation_factor:.2f}")
    print(f"Organization:    {args.org_id}")
    print(f"Site:            {args.site_id}")
    print(f"Zone(s):         {', '.join(args.zone_ids)}")
    print(f"Project:         {args.project_id}")
    print()

    # Generate timestamps
    print("Generating timestamps...")
    timestamps = generate_timestamps(start_date, end_date, args.interval_minutes)
    print(f"  ✓ {len(timestamps)} timestamps generated")

    if len(timestamps) < 2:
        print("Error: Need at least 2 timestamps (start and end)")
        sys.exit(1)

    # Initialize generator
    generator = SensorDataGenerator(correlation_factor=args.correlation_factor)

    # Generate BigQuery rows (all but last timestamp)
    print()
    print("Generating sensor data for BigQuery...")
    rows = generate_bigquery_rows(
        timestamps, args.org_id, args.site_id, args.zone_ids, generator
    )
    num_fields = sum(len(s["fields"]) for s in SENSOR_TEMPLATES.values())
    num_zones = len(args.zone_ids)
    print(f"  ✓ {len(rows)} rows generated ({len(timestamps)-1} timestamps × {num_fields} fields × {num_zones} zones)")
    
    # Show sensor IDs being used per zone
    print()
    print("Sensor IDs per zone:")
    for zone_id in args.zone_ids:
        zone_sensors = get_sensors_for_zone(zone_id)
        sensor_ids = list(zone_sensors.keys())
        print(f"  Zone {zone_id[-8:]}: {len(sensor_ids)} sensors")
        for sensor_id in sensor_ids:
            model = zone_sensors[sensor_id]["model"]
            print(f"    - {sensor_id} ({model})")

    # Bulk insert to BigQuery
    print()
    print("Inserting data to BigQuery...")
    success_count, failed_count = bulk_insert_to_bigquery(rows, args.project_id)
    print(f"  ✓ {success_count} rows inserted successfully")
    if failed_count > 0:
        print(f"  ✗ {failed_count} rows failed")

    # Post last timestamp to ingestData endpoint (once per zone)
    if not args.skip_firestore:
        print()
        print("Posting final data point to ingestData endpoint...")
        last_timestamp = timestamps[-1]
        firestore_success = True
        for zone_id in args.zone_ids:
            print(f"  Zone {zone_id[-8:]}...")
            payload = generate_ingest_payload(
                last_timestamp, args.org_id, args.site_id, zone_id, generator
            )
            success = post_to_ingest_endpoint(payload, args.ingest_endpoint)
            firestore_success = firestore_success and success
    else:
        print()
        print("Skipping Firestore update (--skip-firestore flag set)")
        firestore_success = True

    # Summary
    print()
    print("=" * 70)
    if success_count > 0 and firestore_success:
        print("✓ SUCCESS: Mock data loaded successfully!")
        print()
        print("Next steps:")
        print("  1. Open the Flutter app's Historical Dashboard")
        print("  2. Select the date range and zones")
        print("  3. Verify graphs display the generated data")
    else:
        print("✗ FAILED: Some operations did not complete successfully")
        sys.exit(1)


if __name__ == "__main__":
    main()
