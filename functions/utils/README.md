# Functions Utilities

Testing and development utilities for the Agrivoltaics project.

## Mock Historical Data Loader

### Purpose

The `load_mock_data.py` script generates realistic sensor data for testing the historical dashboard UI without requiring physical sensors. It:

- Generates semi-random sensor readings with configurable point-to-point correlation
- Bulk-inserts data directly to BigQuery (fast and cost-effective)
- Posts the final timestamp to the `ingestData` endpoint to sync Firestore state
- Simulates all 4 Arduino sensors (DHT22, VEML7700, Soil, SGP30) with 8 reading fields

### Installation

1. Install Python dependencies:

```bash
cd functions/utils
pip install -r requirements.txt
```

2. Set up Google Cloud authentication:

```bash
# Download service account key from Firebase Console
# Project Settings > Service Accounts > Generate New Private Key

# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"

# Windows PowerShell:
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\service-account-key.json"
```

### Usage

#### Basic Example

Generate 10 days of data with 15-minute intervals:

```bash
python load_mock_data.py \
  --start-date "2026-02-01T00:00:00Z" \
  --end-date "2026-02-10T23:59:59Z" \
  --interval-minutes 15
```

#### Custom Correlation

Control how smooth the data curves are:

```bash
# Pure random (no correlation between points)
python load_mock_data.py \
  --start-date "2026-02-01T00:00:00Z" \
  --end-date "2026-02-05T00:00:00Z" \
  --correlation-factor 0.0

# Smooth curves (high correlation)
python load_mock_data.py \
  --start-date "2026-02-01T00:00:00Z" \
  --end-date "2026-02-05T00:00:00Z" \
  --correlation-factor 0.9
```

#### Different Time Intervals

```bash
# Hourly data (fewer points, faster generation)
python load_mock_data.py \
  --start-date "2026-01-01T00:00:00Z" \
  --end-date "2026-01-31T23:59:59Z" \
  --interval-minutes 60

# 5-minute data (high resolution)
python load_mock_data.py \
  --start-date "2026-02-11T00:00:00Z" \
  --end-date "2026-02-12T00:00:00Z" \
  --interval-minutes 5
```

#### Skip Firestore Update

For pure BigQuery testing without affecting Firestore:

```bash
python load_mock_data.py \
  --start-date "2026-02-01T00:00:00Z" \
  --end-date "2026-02-10T00:00:00Z" \
  --skip-firestore
```

### Command-Line Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--start-date` | Yes | - | Start date in ISO 8601 format (e.g., `2026-02-01T00:00:00Z`) |
| `--end-date` | Yes | - | End date in ISO 8601 format |
| `--interval-minutes` | No | 15 | Minutes between data points |
| `--correlation-factor` | No | 0.7 | Point-to-point correlation (0.0-1.0): 0.0=pure random, 1.0=smooth |
| `--org-id` | No | `GS6e4032WK70vQ42WTYc` | Organization ID |
| `--site-id` | No | `5LvgyAAaFpAmlfcUrpTU` | Site ID |
| `--zone-id` | No | `7aZzv6juGouqsbicdC8J` | Zone ID |
| `--project-id` | No | `agrivoltaics-flutter-firebase` | GCP project ID |
| `--ingest-endpoint` | No | Production URL | ingestData cloud function endpoint |
| `--skip-firestore` | No | False | Skip posting last data point to Firestore |

### Generated Sensor Data

The script simulates all 4 Arduino sensors with realistic value ranges:

#### Sensor 1: DHT22 Weather Sensor
- **Temperature**: 50-85°F with diurnal pattern (warmer during day)
- **Humidity**: 40-80%

#### Sensor 2: VEML7700 Light Sensor
- **Light**: 100-80,000 lux with strong diurnal pattern (bright during day)

#### Sensor 3: Soil Sensor
- **Soil Moisture**: 30-70% VWC
- **Soil Temperature**: 55-75°F with dampened diurnal pattern
- **Soil EC**: 800-2,000 μS/cm

#### Sensor 4: SGP30 Air Quality
- **CO2**: 400-800 ppm
- **TVOC**: 0-150 ppm

### Diurnal Patterns

Fields with `diurnal: true` use a sine wave based on hour-of-day:
- Peak around 14:00 (2 PM)
- Trough around 02:00 (2 AM)
- ±30% of value range

This creates realistic day/night cycles for temperature and light.

### Correlation Factor Explained

The correlation factor controls how much each new value depends on the previous value:

- **0.0 (Pure Random)**: Each point is completely independent
  - Pros: Simple, tests edge cases
  - Cons: Unrealistic jumps, jagged graphs

- **0.5 (Moderate)**: Balanced between correlation and randomness
  - Good for general testing

- **0.7 (Default)**: Realistic sensor behavior
  - Values drift gradually
  - Small random variations
  - Smooth but not perfectly smooth

- **0.9+ (High)**: Very smooth curves
  - Minimal point-to-point variation
  - Good for testing graph rendering

**Technical**: `new_value = prev_value * factor + random_value * (1 - factor) + small_random_walk`

### Usage in Automated Tests

#### Python Test Script

```python
import subprocess
from datetime import datetime, timedelta

def load_test_data():
    """Load mock data for test environment."""
    end_date = datetime.utcnow()
    start_date = end_date - timedelta(days=7)
    
    result = subprocess.run([
        "python", "functions/utils/load_mock_data.py",
        "--start-date", start_date.isoformat() + "Z",
        "--end-date", end_date.isoformat() + "Z",
        "--interval-minutes", "30",
        "--correlation-factor", "0.8",
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise Exception(f"Failed to load mock data: {result.stderr}")
    
    print("Test data loaded successfully")
```

#### Shell Script

```bash
#!/bin/bash
# setup_test_data.sh

# Load last 30 days of data
python functions/utils/load_mock_data.py \
  --start-date "$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --interval-minutes 15 \
  --correlation-factor 0.7

echo "Test environment ready"
```

### Verification

After running the script:

1. **Check BigQuery**:
   ```sql
   SELECT 
     field,
     COUNT(*) as count,
     MIN(timestamp) as first_reading,
     MAX(timestamp) as last_reading,
     AVG(value) as avg_value
   FROM `agrivoltaics-flutter-firebase.sensor_data.readings`
   WHERE timestamp >= '2026-02-01'
   GROUP BY field
   ORDER BY field;
   ```

2. **Check Flutter App**:
   - Open Historical Dashboard
   - Select date range matching your generated data
   - Select the zone (Zone 7aZzv6juGouqsbicdC8J by default)
   - Select reading fields (temperature, humidity, etc.)
   - Verify graphs display data with expected patterns

3. **Check Firestore**:
   - Navigate to sensor documents in Firestore Console
   - Verify `isOnline = true`
   - Verify `lastReading` timestamp matches your end date
   - Verify `fields.*.currentValue` populated with last values

### Performance & Cost

- **BigQuery Streaming Inserts**: ~$0.01 per 200 MB
  - ~500 bytes per row
  - 10,000 rows ≈ 5 MB ≈ negligible cost

- **Execution Time**:
  - 1 week of 15-min data: ~672 timestamps × 8 fields = 5,376 rows → ~5 seconds
  - 1 month: ~21,000 rows → ~15 seconds
  - 1 year: ~252,000 rows → ~3 minutes (batched)

- **Storage**:
  - 1 year of data: ~250K rows × 500 bytes ≈ 125 MB
  - BigQuery storage: ~$0.02/GB/month = ~$0.0025/month

### Troubleshooting

#### Authentication Error

```
google.auth.exceptions.DefaultCredentialsError
```

**Solution**: Set `GOOGLE_APPLICATION_CREDENTIALS` environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

#### BigQuery Permission Error

```
403 Forbidden: Permission denied
```

**Solution**: Ensure service account has roles:
- BigQuery Data Editor
- BigQuery Job User

#### ingestData Endpoint 400 Error

**Possible causes**:
- Sensor documents don't exist in Firestore
- Sensors not marked as `status: "active"`
- Invalid organizationId/siteId/zoneId

**Solution**: Verify Firestore sensor documents exist and are active.

#### Too Many Rows Error

```
Request payload size exceeds the limit
```

**Solution**: Script automatically batches at 10,000 rows. If still failing, date range is too large. Split into multiple runs.

### Best Practices

1. **Start Small**: Test with 1 day of data first
2. **Match Reality**: Use 15-minute intervals to match Arduino behavior
3. **Correlation**: Use 0.7-0.8 for realistic testing
4. **Verification**: Always verify data in BigQuery before testing UI
5. **Automation**: Integrate into CI/CD or test setup scripts
6. **Cleanup**: Delete old test data periodically to manage costs

### Examples for Different Scenarios

#### UI Development (Short Range)
```bash
# Past 3 days, smooth curves for visual testing
python load_mock_data.py \
  --start-date "2026-02-09T00:00:00Z" \
  --end-date "2026-02-12T00:00:00Z" \
  --correlation-factor 0.85
```

#### Performance Testing (Large Dataset)
```bash
# Entire year, hourly data
python load_mock_data.py \
  --start-date "2025-01-01T00:00:00Z" \
  --end-date "2025-12-31T23:59:59Z" \
  --interval-minutes 60 \
  --correlation-factor 0.8
```

#### Edge Case Testing (Noisy Data)
```bash
# Random values with no correlation
python load_mock_data.py \
  --start-date "2026-02-11T00:00:00Z" \
  --end-date "2026-02-12T00:00:00Z" \
  --interval-minutes 5 \
  --correlation-factor 0.0
```

#### Demo Data (Recent + Realistic)
```bash
# Past 2 weeks with good patterns
python load_mock_data.py \
  --start-date "2026-01-29T00:00:00Z" \
  --end-date "2026-02-12T12:00:00Z" \
  --correlation-factor 0.75
```

## Other Utilities

Additional testing utilities can be added to this directory following the same patterns.
