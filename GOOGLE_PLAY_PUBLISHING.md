# Publishing Agrivoltaics to Google Play Store

This guide walks you through publishing your Flutter app to the Google Play Store.

## 📋 Prerequisites Checklist

Before you start, verify you have:

- [ ] Google Play Developer account created ($25 one-time fee paid)
- [ ] App signing keystore created (`agrivoltaics-release.jks`)
- [ ] Signed Android App Bundle (`.aab` file) built and ready
- [ ] App icon (512x512 PNG, at least)
- [ ] 2-4 screenshots (1080x1920 or 1440x2560 pixels)
- [ ] App description (short and long form)
- [ ] Privacy policy created and hosted (we already have this)
- [ ] Consent to Google Play Policies

---

## Step 1: Prepare Your App Bundle

### Build the Signed AAB

Before publishing, you need a signed Android App Bundle. Run this command:

```bash
# From your project root directory
flutter build appbundle --release
```

This creates `build/app/outputs/bundle/release/app-release.aab`

**If the build fails**, see "Fixing Build Errors" section below.

---

## Step 2: Log In to Google Play Console

1. Go to **[Google Play Console](https://play.google.com/console)**
2. Sign in with your Google account (the one used to create the developer account)
3. You should see **"All apps"** dashboard

---

## Step 3: Create the App Listing

### 3.1 Start a New App

1. Click **"Create app"** button (top right)
2. Fill in app details:
   - **App name**: "Agrivoltaics"
   - **Default language**: English
   - **App category**: Agriculture or Lifestyle → Farming
   - **App type**: Choose **Free**
3. Accept Google Play Policies
4. Click **"Create app"**

### 3.2 Complete the Store Listing

You'll be taken to the app overview. Now fill in all sections in the left menu:

#### **Store Listing** (main info)

1. Click **"Store listing"** in left menu
2. Fill in every field:

**Title**:
- "Agrivoltaics" (50 chars max)

**Short description** (80 chars):
- "Monitor your farm with AI-powered crop health analytics and real-time sensor data"

**Full description** (4000 chars):
```
Agrivoltaics is an integrated monitoring and analytics platform for farmers. 

Monitor multiple vineyard and farm locations in real-time with:
• Real-time sensor data (temperature, humidity, soil moisture, light)
• AI-powered disease detection (powdery mildew, downy mildew, black rot)
• Beautiful charts and trends
• Team collaboration and notes
• Weather alerts and critical warnings
• Data export for analysis

Features:
- Live sensor dashboards for multiple sites
- Historical data analysis over days/weeks/months
- Create field observations with photos and notes
- Invite team members and manage permissions
- Critical alerts for sensor failures and unsafe conditions
- Export data in CSV/JSON/PDF formats
- Dark mode and timezone support

Perfect for small-scale and commercial farming operations looking to improve crop health and optimize farming practices.

Privacy: https://github.com/yourusername/agrivoltaics/blob/main/PRIVACY_POLICY.md
```

**App icon** (512x512 PNG):
- Click "Upload" and select your app icon
- Icon should have no transparent areas on edges

**Feature graphic** (1024x500 PNG):
- Optional but recommended
- Create a simple banner showing key features

**Screenshots**:
1. Click "Add screenshots"
2. Upload 2-4 screenshots showing:
   - Dashboard with sensor data
   - Charts and analytics
   - Team collaboration features
   - Alerts/notifications
3. Screenshots should be:
   - 1080x1920 (phone) or 1440x2560 (tablet)
   - Actual screenshots from your app
   - Text overlay optional but helpful

**Video preview**:
- Optional, skip for now

**Category**: 
- Select "Productivity" or "Lifestyle"

**Contact email**:
- Your support email

**Website**:
- Optional, can leave blank

**Email for privacy policy**:
- Your support email

**Privacy policy URL**:
- Link to your PRIVACY_POLICY.md on GitHub
- Example: `https://raw.githubusercontent.com/yourusername/agrivoltaics/main/PRIVACY_POLICY.md`

3. Click **"Save"** at the top

---

## Step 4: Create an App Release

### 4.1 Navigate to Releases

1. Click **"Releases"** in the left sidebar under "Testing"
2. Choose **"Production"** (the main store listing)
3. Click **"Create new release"**

### 4.2 Add Your AAB File

1. Under **"App bundles"**, click **"Browse files"**
2. Navigate to: `build/app/outputs/bundle/release/app-release.aab`
3. Select and upload the file
4. Wait for upload to complete (shows green checkmark)

### 4.3 Review Release Notes

1. Scroll to **"Release notes"**
2. Enter notes for this release:
   ```
   Initial release of Agrivoltaics to Google Play Store
   
   Features:
   - Real-time sensor monitoring for multiple farm sites
   - AI-powered crop disease detection
   - Team collaboration and field observations
   - Historical data analysis and charts
   - Critical alerts and notifications
   ```

### 4.4 Review & Confirm

1. Scroll to top and review all information
2. Click **"Review"** to check for errors
3. Google Play will validate your AAB:
   - Check app signing
   - Verify package name
   - Scan for security issues
4. Once validated (green checkmark), click **"Release to Production"**

---

## Step 5: Complete Content Rating

### 5.1 Fill Out Questionnaire

1. Click **"Content rating"** in left sidebar
2. Click **"Set up your content rating"**
3. Fill out the questionnaire:
   - Company name: Your name/organization
   - Email: Your contact email
   - Select content categories:
     - Violence: None
     - Profanity: None
     - Restricted content: None
     - Other: None
4. Click **"Save questionnaire"**
5. You'll get a content rating certificate
6. Click **"Apply rating"** to apply to your app

---

## Step 6: Set Up Pricing & Distribution

### 6.1 Pricing

1. Click **"Pricing and distribution"** in left sidebar
2. **Price**: Choose **"Free"**
3. Click **"Save"**

### 6.2 Countries & Regions

1. Check countries where you want to distribute:
   - By default, all countries are selected
   - You can deselect specific countries if needed
   - Most apps keep all countries
2. Click **"Save"**

---

## Step 7: Check for Required Settings

Before submitting, verify all required sections are complete:

1. Go to **"App content"** in left sidebar
2. Check all items are filled:
   - [ ] Ads
   - [ ] Data types
   - [ ] Data safety details
   - [ ] Data security

### Complete Data Safety Section

1. Click **"Data safety"**
2. Answer questions about data collection:
   - **Does your app collect personal data?** Yes
   - **Personal data types collected**:
     - Name: Yes
     - Email: Yes
     - Location: Yes (optional)
   - **Data is encrypted**: Yes (in transit and at rest)
   - **Data retention**: Describe your policy
   - **Deletion policy**: Users can delete their account
3. Click **"Save"**

---

## Step 8: Submit for Review

### 8.1 Final Checklist

Before submitting, verify:

- [ ] Store listing completely filled
- [ ] App icon uploaded (512x512)
- [ ] Screenshots uploaded (2-4 minimum)
- [ ] Content rating questionnaire completed
- [ ] Privacy policy URL set
- [ ] App bundle uploaded and validated
- [ ] Pricing set to Free
- [ ] Countries selected
- [ ] Data safety section completed
- [ ] No errors in review section

### 8.2 Submit the App

1. Go to **"Releases"** → **"Production"**
2. Review your release one more time
3. Click **"Review"** button (blue at top)
4. Google Play will do final validation
5. If all checks pass, click **"Release to Production"**
6. Confirm the dialog

### 8.3 Monitor Review Process

1. Your app goes into review (usually 1-24 hours)
2. You'll receive an email when review completes
3. If rejected, you'll get specific reasons to fix
4. If approved, app becomes live on Google Play!

---

## Step 9: Monitor Your App

Once live, you can monitor:

1. **Statistics**: Download count, rating, crashes
2. **Ratings & Reviews**: See user reviews and respond
3. **Crashes & ANRs**: Monitor app stability
4. **User Feedback**: See where users are from, devices used

---

## Common Rejection Reasons & Fixes

| Issue | Fix |
|-------|-----|
| **Missing privacy policy** | Add complete privacy policy URL in store listing |
| **App crashes on startup** | Test thoroughly before uploading AAB |
| **Misleading content** | Description must accurately represent app |
| **Ads not disclosed** | If using ads, clearly mention in description |
| **Excessive permissions** | Remove unnecessary Android permissions in AndroidManifest.xml |
| **Non-functional features** | All described features must work |

---

## Fixing Build Errors

If `flutter build appbundle --release` fails, try:

### 1. Clean Build

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

### 2. Check Settings.gradle

The `android/settings.gradle` should have pluginManagement at the very top:

```gradle
pluginManagement {
    includeBuild(System.getenv("FLUTTER_ROOT") + "/packages/flutter_tools/gradle")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
}

include ':app'
// Rest of file...
```

### 3. Check Version Numbers

In `android/app/build.gradle`, verify:

```gradle
android {
    compileSdkVersion 34  // or latest stable
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "1.0.0"
    }
}
```

### 4. Verify Signing Configuration

In `android/app/build.gradle`:

```gradle
signingConfigs {
    release {
        keyAlias = 'agrivoltaics'
        keyPassword = 'YOUR_KEY_PASSWORD'
        storeFile = file('../../.android/agrivoltaics-release.jks')
        storePassword = 'YOUR_STORE_PASSWORD'
    }
}

buildTypes {
    release {
        signingConfig = signingConfigs.release
    }
}
```

### 5. Run Verbose Build

If still failing:

```bash
flutter build appbundle --release -v 2>&1 | head -100
```

This shows the first 100 lines of errors. Share those with support if needed.

---

## Version Updates

When you want to release a new version:

1. Increment version in `android/app/build.gradle`:
   ```gradle
   versionCode 2  // Increment by 1
   versionName "1.0.1"  // Update version name
   ```

2. Rebuild the AAB:
   ```bash
   flutter build appbundle --release
   ```

3. Go to **Releases** → **Production**
4. Click **"Create new release"**
5. Upload the new AAB
6. Add release notes
7. Click **"Review"** → **"Release to Production"**

---

## Troubleshooting

### "App bundle rejected: Invalid signature"
- Ensure you're using the correct keystore password
- Verify the keystore file exists at the path specified

### "Version code must be higher than previous release"
- Each new release must have a higher versionCode
- In `android/app/build.gradle`, increment versionCode by 1

### "App crashes on first launch"
- Test the app thoroughly on a real device before uploading
- Check for obvious errors in `flutter run`

### "Pending publication takes too long"
- Normal review time: 1-24 hours
- Check email for rejection reasons if it takes longer
- Contact Google Play support if stuck

---

## Next Steps After Publishing

1. **Monitor reviews** – Respond to user feedback
2. **Watch crashes** – Check Crashes & ANRs section weekly
3. **Plan updates** – Increment versionCode and publish new versions
4. **Grow your user base** – Share on social media, ask friends to review

---

**Congratulations!** Your app is now on Google Play Store! 🎉
