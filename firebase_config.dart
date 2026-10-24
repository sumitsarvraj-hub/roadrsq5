
import 'package:firebase_core/firebase_core.dart';

// ====== Firebase project: raodrsq ======
const _apiKey = 'AIzaSyAvfftIm5A9Ji6uRqBQPvX2qpEts-eQo7w';
const _appId = '1:255237821125:android:f86de92074961a2d63d6ac';
const _senderId = '255237821125';
const _projectId = 'raodrsq';
// =======================================

bool get firebaseConfigured => !_apiKey.startsWith('PASTE');

const firebaseOptions = FirebaseOptions(
  apiKey: _apiKey,
  appId: _appId,
  messagingSenderId: _senderId,
  projectId: _projectId,
);
