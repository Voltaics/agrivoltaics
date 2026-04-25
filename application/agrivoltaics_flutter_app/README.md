# Agrivoltaics Flutter App

Primary client application for organization management, sensor monitoring, alerts, and historical analytics.

## Scope

This is the active Flutter app for the project.

For full handoff context, read:

- ../../docs/Developer-Handoff.md
- ../../docs/Applicable-Software.md
- ../../docs/DataModel.md

## Prerequisites

- Flutter SDK
- Dart SDK (project constraint: >=3.0.0 <4.0.0)
- Access to Firebase project agrivoltaics-flutter-firebase

## Run Locally

```bash
flutter pub get
flutter run -d chrome
```

## Useful Commands

```bash
flutter analyze
flutter test
```

## Runtime Configuration (dart-define)

Environment-backed values are read from lib/app_constants.dart.

Commonly used:

- HISTORICAL_SERIES_ENDPOINT
- FROST_PREDICTION_SERIES_ENDPOINT
- TIMEZONE

Example:

```bash
flutter run -d chrome \
	--dart-define=HISTORICAL_SERIES_ENDPOINT=https://us-central1-agrivoltaics-flutter-firebase.cloudfunctions.net/getHistoricalSeries \
	--dart-define=FROST_PREDICTION_SERIES_ENDPOINT=https://us-central1-agrivoltaics-flutter-firebase.cloudfunctions.net/getFrostPredictionSeries
```

## Notes

- Firebase options are configured in lib/firebase_options.dart.
- Legacy/prototype Flutter apps exist elsewhere in the repository and are not the primary development target.
