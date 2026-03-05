import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:agrivoltaics_flutter_app/influx.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';

Future<UserCredential> signInWithGoogleWeb() async {
  getIt = GetIt.instance;
  GoogleAuthProvider googleAuthProvider = getIt.get<GoogleAuthProvider>();

  return await FirebaseAuth.instance.signInWithPopup(googleAuthProvider);
}

Future<void> signOut() async {
  await FirebaseAuth.instance.signOut();
}

// Future<UserCredential> signInWithGoogleMobile() async {
//   final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
//   final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

//   final credential = GoogleAuthProvider.credential(
//     accessToken: googleAuth?.accessToken,
//     idToken: googleAuth?.idToken
//   );

//   return await FirebaseAuth.instance.signInWithCredential(credential);
// }

bool authorizeUser(UserCredential userCredential) {
  var userEmail = userCredential.user?.email;
  return (AppConstants.authorizedEmails.contains(userEmail));
}