# Applicable Software (Canonical)

Canonical software supporting this application is Firebase and Google Cloud.

Can login to both using GrafanaInfluxDB Google account (agrivoltaicsgrafana@gmail.com) whose creds are in the shared Google Drive.

Ideally, every user can login with their own account down the road.

## Firebase

Important parts in Firebase:

- FireStore
- Authentication
- CFM
- Storage

## Google Cloud

Important part in Google Cloud:

- BigQuery

Google Cloud also hosts the web application.

Web app URL:

- https://vinovoltaics-webapp-593883469296.us-east4.run.app/

To access the web app, make sure you're email is in the AUTHORIZED_EMAILS whitelist environment variable and deploy using the GitHub CD pipeline.

## Project

The project in both Firebase and Google Cloud that you should be working with is:

- agrivoltaics-flutter-firebase

## GitHub

GitHub is our source control host. All developers will need access. Link:

 - https://github.com/Voltaics/agrivoltaics