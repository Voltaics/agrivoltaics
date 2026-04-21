# Agrivoltaics Project — Backlog Handover

> **Purpose:** This document summarizes outstanding backlog items for the Agrivoltaics project to be handed off to the next team. Items are grouped by category and include priority/type indicators where applicable.

---

## Table of Contents

1. [Security & Authentication](#1-security--authentication)
2. [Infrastructure & DevOps](#2-infrastructure--devops)
3. [Permissions & Access Control](#3-permissions--access-control)
4. [Alerts & Notifications](#4-alerts--notifications)
5. [Sensor & Data Management](#5-sensor--data-management)
6. [UI / UX Issues](#6-ui--ux-issues)
7. [Image Data & Model Training](#7-image-data--model-training)
8. [Frost Model](#8-frost-model)
9. [Monetization & Rate Limiting](#9-monetization--rate-limiting)
10. [Test Automation](#10-test-automation)

---

## 1. Security & Authentication

### 🔐 Add Authentication to All Firebase Cloud Functions
All Firebase Cloud Functions currently lack authentication. Authentication needs to be added to secure the API surface before any external users begin using the platform. This is also a **prerequisite** for rate limiting and billing features (see [Monetization & Rate Limiting](#9-monetization--rate-limiting)).

---

### 🐛 Google Authentication Initialization State Error (iPhone Home Screen)
**Type:** Bug

When logging in with Google while running the web app via the iPhone home screen (PWA mode), an initialization state error occurs. The bug has so far only been reproduced in this specific context and has not been observed in standard browser sessions. Further investigation is needed to determine root cause and whether it affects other non-standard launch contexts.

---

### 📋 Actions on the Email Whitelist
Currently, a whitelist is enforced via the `AUTHORIZED_EMAILS` environment variable. The next team will need to make a product decision on:

- Whether to keep the whitelist approach at all.
- If retained, how to maintain it (e.g., move to a database, an admin UI, or a config file in source control).

---

## 2. Infrastructure & DevOps

### ☁️ Set Up Access Control in Google Cloud
Configure Google Cloud IAM so that each team member can use their own account to manage resources. It is recommended to create developer groups to simplify permission assignment and reduce individual access management overhead.

---

### 🌿 Add Repository Protections and Branching Strategy in GitHub
Define and enforce a branching strategy (e.g., `main` / `develop` / feature branches). Add branch protection rules to prevent direct pushes to protected branches and require pull request reviews.

---

### 🏗️ Create a Non-Production Environment
A non-prod (staging/development) environment does not currently exist. One should be created to allow safe testing of features before they reach production.

---

## 3. Permissions & Access Control

### 🔒 Organization-Level Permissions Are Not Enforced
**Type:** Bug / Enhancement

Permissions within an organization are currently non-functional. Members at the lowest access level are able to perform owner-level actions such as adding and removing owners. Role-based access control needs to be implemented and enforced.

---

## 4. Alerts & Notifications

### ✨ Replace Cooldown Concept with Repeats Concept on Alerts Page
**Type:** Enhancement

On the Alerts page, the current "cooldown" concept should be replaced with a "repeats" concept to better reflect the intended user experience. Design and implementation details to be determined by the next team.

---

### 🔔 Continue Building Alerts Device Notifications Feature
The alerts device notifications feature is partially implemented and likely contains bugs. The next team should audit the current implementation, identify and resolve any bugs, and continue building out the feature to completion.

---

## 5. Sensor & Data Management

### 📐 Round Historical Data Values to Consistent Significant Digits
On the historical data graphs and stationary sensors page, displayed values need to be rounded to a consistent number of significant digits. Mohsen initially recommended 2 significant digits, but this was found to drop important precision. A solution that balances readability and accuracy needs to be determined.

---

### 🗂️ Update Sensor Lookup Structure in Data Model
Currently, the document ID for the sensor lookup object uses `sensorId`. This should be changed to `sensorLookupId` because a given sensor may be transitioned to another zone. `SensorLookup` should be unique for a given org + site + zone + sensor combination.

> ⚠️ **Note:** This change may be out of date relative to current development. The next team should assess whether it is still applicable before proceeding.

---

### ➕ Add Interface to Create Readings
Currently, adding a new reading requires a developer to manually insert it in the backend readings table. An interface should be created in the application to allow readings to be added without direct backend access. A prerequisite is establishing a table as the source of truth for readings.

---

### 🌾 Simplify Adding Sensors
Arduino code is currently hardcoded, and the IDs connecting physical sensors to their database entities are hardcoded as well. A long-term goal is to create an onboarding process for connecting sensors that is simple enough for a non-technical farmer to complete without developer assistance.

---

### 📦 Create Historical Data Aggregation Routine
After two months have elapsed, a routine should aggregate sensor readings into a single daily reading per sensor. All data for the day should be exported to low-cost storage (e.g., Google Cloud Storage, S3). This will reduce database costs as historical data grows.

---

## 6. UI / UX Issues

### 🐛 Historical Data Graphs Reset on Screen Orientation Change (Mobile)
**Type:** Bug

On mobile, switching between portrait and landscape orientations causes data query values to reset and graphs to disappear, requiring the user to re-query. This issue is likely also present when resizing a desktop browser window. The application state (query parameters and loaded data) should be preserved across screen size transitions.

---

## 7. Image Data & Model Training

### 🖼️ Create Interface for Inputting and Managing Image Data
An interface is needed within the application to:

- Upload image data to the cloud.
- Manage stored images.
- Pair metadata with images (e.g., disease state, date, location, or other attributes relevant to model training).

This will support future machine learning workflows for the agrivoltaics platform.

The AI Models will need to be trained with more imgaes that are taken in the vineyard to be more accurate.

The pest_detection model could be trained to detect additional pests such as phylloxera, grape berry moth, etc.
---

## 8. Frost Model

### 🌡️ Add Frost Model Settings to the App
Users need to be able to configure frost model parameters directly from the application. This includes toggling whether the farmer has deployed frost candles for storage and adjusting other relevant model parameters.

---

### 📝 Store Data on Fan and Frost Candle Deployment
To improve the frost model, the application should record when a farmer puts out fans or frost candles. An interface in the app is required to capture this input and associate it with timestamps for use in model training and validation.

---

## 9. Monetization & Rate Limiting

### 💳 Rate Limiting and External User Billing
**Dependency:** Requires authentication on Cloud Functions to be completed first.

Once authentication is in place, consider:

- Rate limiting the API to prevent abuse.
- Charging external users for API usage.
- Billing organizations based on storage usage.

These features become important before the platform is opened to external users.

---

## 10. Test Automation

### 🧪 Add a Test Automation Suite
**Type:** Recommendation

The project currently has no automated tests of any kind — no unit tests, integration tests, or end-to-end tests. The next team is strongly encouraged to establish a test automation suite early in their engagement. Some areas to prioritize:

- **Unit tests** — Cover core business logic such as frost model calculations, sensor data processing, alert evaluation, and permission checks.
- **Integration tests** — Verify that Firebase Cloud Functions, Firestore reads/writes, and authentication flows behave correctly together.
- **End-to-end tests** — Simulate key user journeys (e.g., login, viewing historical data, creating alerts) to catch regressions in the UI.
- **Automated UI tests** — Flutter has built-in support for widget and integration tests, making it straightforward to automate UI testing. This is a good opportunity to take advantage of the framework and catch UI regressions early.

Introducing tests now will make it significantly safer to address the other backlog items in this document, particularly the data model changes, permissions enforcement, and Cloud Function authentication work.

---

*Last updated: April 2026 — Prepared for handover to the next development team.*
