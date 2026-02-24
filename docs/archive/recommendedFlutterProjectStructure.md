lib/
├── main.dart                          # App entry point
├── app.dart                           # Root MaterialApp widget
│
├── models/                            # Data models (PODOs - Plain Old Dart Objects)
│   ├── user.dart
│   ├── organization.dart
│   ├── site.dart
│   ├── zone.dart
│   ├── sensor.dart
│   ├── alert.dart
│   └── notification.dart
│
├── services/                          # Business logic & external APIs ⭐ PUT FIRESTORE HERE
│   ├── auth_service.dart              # Firebase Auth operations
│   ├── firestore_service.dart         # Generic Firestore helpers
│   ├── user_service.dart              # User CRUD operations
│   ├── organization_service.dart      # Organization CRUD operations
│   ├── site_service.dart              # Site CRUD operations
│   ├── sensor_service.dart            # Sensor CRUD operations
│   ├── alert_service.dart             # Alert operations
│   ├── influx_service.dart            # InfluxDB operations (your existing influx.dart)
│   └── storage_service.dart           # Firebase Storage operations
│
├── providers/                         # State management (if using Provider/Riverpod)
│   ├── auth_provider.dart
│   ├── organization_provider.dart
│   └── sensor_provider.dart
│
├── screens/ (or pages/)               # Full-page widgets ⭐ YOUR EXISTING pages/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   ├── home/
│   │   ├── home_screen.dart
│   │   └── dashboard_screen.dart
│   ├── organizations/
│   │   ├── organization_list_screen.dart
│   │   ├── organization_detail_screen.dart
│   │   └── create_organization_screen.dart
│   ├── sites/
│   │   ├── site_list_screen.dart
│   │   └── site_detail_screen.dart
│   └── sensors/
│       ├── sensor_list_screen.dart
│       └── sensor_detail_screen.dart
│
├── widgets/                           # Reusable UI components
│   ├── common/
│   │   ├── loading_indicator.dart
│   │   └── error_widget.dart
│   ├── sensor_card.dart
│   ├── site_card.dart
│   └── notification_badge.dart
│
├── utils/                             # Helper functions, constants
│   ├── constants.dart
│   ├── validators.dart
│   └── formatters.dart
│
└── config/                            # Configuration files
    ├── app_config.dart
    └── firebase_options.dart          # Your existing firebase_options.dart