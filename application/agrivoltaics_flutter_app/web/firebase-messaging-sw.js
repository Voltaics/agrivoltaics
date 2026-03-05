// Firebase Messaging Service Worker
// Required for FCM push delivery when the app tab is closed.
// This file must live at the root of the web/ directory so it is served
// at /firebase-messaging-sw.js by the Flutter web server.

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBNJGg2wwE17ohi3W_C0r7LYR2M6M7bdM4',
  authDomain: 'agrivoltaics-flutter-firebase.firebaseapp.com',
  projectId: 'agrivoltaics-flutter-firebase',
  storageBucket: 'agrivoltaics-flutter-firebase.appspot.com',
  messagingSenderId: '593883469296',
  appId: '1:593883469296:web:228da2060c5e674174b935',
});

const messaging = firebase.messaging();

// Handle background messages (tab closed or app not in focus).
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'Vinovoltaics Alert';
  const body = payload.notification?.body ?? '';
  const icon = '/icons/Icon-192.png';

  self.registration.showNotification(title, {body, icon});
});
