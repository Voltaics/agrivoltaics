import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import '../../../app_state.dart';

class AppNotificationBody {
  // Placeholder class for notification body structure
  AppNotificationBody();

  factory AppNotificationBody.fromJson(Map<String, dynamic> json) {
    return AppNotificationBody();
  }
}

/// Data class for app notification settings
class AppSettings {
  AppSettings(this.body, this.siteChecked);
  
  AppNotificationBody body;
  String siteChecked;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      AppNotificationBody.fromJson(json['settings']),
      json['site1'].toString().split('/')[0],
    );
  }
}

/// Fetches user settings from the notification API
/// 
/// Retrieves organization, site, zone, and notification preferences
/// Updates the provided AppState with the fetched settings
Future<void> getSettings(String? email, AppState appstate) async {
  try {
    http.Response response = await http.get(
      Uri.parse(
        'https://vinovoltaics-notification-api-6ajy6wk4ca-ul.a.run.app/getSettings?email=$email',
      ),
    );

    if (response.statusCode == 200) {
      appstate.sites = [];
      bool siteChecked = false;
      String siteNickName;
      bool zoneChecked = false;
      String zoneNickName;
      bool temperature = false;
      bool humidity = false;
      bool frost = false;
      bool rain = false;
      bool soil = false;
      bool light = false;

      for (int i = 0; i < jsonDecode(response.body)['settings'].length - 3; i++) {
        for (int j = 0;
            j < jsonDecode(response.body)['settings']['site${i+1}'].length - 2;
            j++) {
          siteChecked = json.decode(response.body)['settings']['site${i+1}']['site_checked'];
          siteNickName =
              json.decode(response.body)['settings']['site${i+1}']['nickName'];
          zoneChecked = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['zone_checked'];
          zoneNickName = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['nickName'];
          temperature = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['temperature'];
          humidity = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['humidity'];
          frost = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['frost'];
          rain = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['rain'];
          soil = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['soil'];
          light = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['light'];

          if (j == 0) {
            appstate.addSiteFromDB(
              siteChecked,
              siteNickName,
              zoneChecked,
              zoneNickName,
              humidity,
              temperature,
              light,
              frost,
              rain,
              soil,
            );
          } else {
            appstate.addZoneFromDB(
              i,
              zoneChecked,
              zoneNickName,
              humidity,
              temperature,
              light,
              frost,
              rain,
              soil,
            );
          }
        }
      }

      appstate.singleGraphToggle =
          json.decode(response.body)['settings']['singleGraphToggle'];
      appstate.timezone = tz.getLocation(
        json.decode(response.body)['settings']['timeZone'],
      );
      appstate.returnDataValue =
          json.decode(response.body)['settings']['returnDataFilter'];
    }
  } catch (e) {
    print('Error fetching settings: $e');
  }
}
