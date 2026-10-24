import 'package:firebase_core/firebase_core.dart';

// ====== YAHAN APNI 4 FIREBASE VALUES DAALEIN (google-services.json se) ======
const _apiKey = 'PASTE_API_KEY_HERE';              // current_key
const _appId = 'PASTE_APP_ID_HERE';                // mobilesdk_app_id
const _senderId = 'PASTE_PROJECT_NUMBER_HERE';     // project_number
const _projectId = 'PASTE_PROJECT_ID_HERE';        // project_id
// ===========================================================================

bool get firebaseConfigured => !_apiKey.startsWith('PASTE');

const firebaseOptions = FirebaseOptions(
  apiKey: _apiKey,
  appId: _appId,
  messagingSenderId: _senderId,
  projectId: _projectId,
);
