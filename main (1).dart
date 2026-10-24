import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_config.dart';

// ============ 1. THEME (prototype wala same look) ============
const bg = Color(0xFFEEF1F4);
const ink = Color(0xFF1B2430);
const mute = Color(0xFF5D6B7C);
const line = Color(0xFFD5DCE4);
const blue = Color(0xFF1F5FBF);
const red = Color(0xFFD62F2F);
const yel = Color(0xFFF5C518);
const ok = Color(0xFF1D8A4E);

TextStyle head(double s) =>
    GoogleFonts.barlowCondensed(fontSize: s, fontWeight: FontWeight.w700, color: ink);

// ============ 2. DATA MODELS ============
class Cat {
  final String id, icon, name;
  final int lo, hi;
  const Cat(this.id, this.icon, this.name, this.lo, this.hi);
}

const cats = [
  Cat('puncture', '🔧', 'Puncture', 80, 150),
  Cat('battery', '🔋', 'Battery', 100, 200),
  Cat('fuel', '⛽', 'Fuel', 60, 120),
  Cat('breakdown', '🚗', 'Breakdown', 150, 300),
  Cat('towing', '🚚', 'Towing', 300, 800),
  Cat('mechanic', '🛠️', 'Mechanic', 100, 250),
  Cat('accident', '🏥', 'Accident', 0, 0),
];
Cat catOf(String id) => cats.firstWhere((c) => c.id == id);

class Svc {
  final String id, shop;
  final List<String> cats;
  final double dLat, dLng;
  final int fee;
  bool online;
  double rating;
  int n;
  String status;
  Svc(this.id, this.shop, this.cats, this.dLat, this.dLng, this.fee,
      {this.online = true, this.rating = 4.5, this.n = 10, this.status = 'approved'});
}

class Req {
  final int id, visit;
  final String cat, pid, when;
  final double lat, lng;
  String status = 'pending';
  int? finalCost, rating;
  String review = '';
  Req(this.id, this.cat, this.pid, this.visit, this.when, this.lat, this.lng);
}

class Diag {
  final List<String> cause;
  final String cat;
  Diag(this.cause, this.cat);
}

// ============ 3. LOGIC ============
double km(double a1, double o1, double a2, double o2) {
  double r(double x) => x * pi / 180;
  final dLa = r(a2 - a1), dLo = r(o2 - o1);
  final h = pow(sin(dLa / 2), 2) + cos(r(a1)) * cos(r(a2)) * pow(sin(dLo / 2), 2);
  return 2 * 6371 * asin(sqrt(h));
}

// Prototype AI: keywords. Baad mein yahan asli AI API call lagegi.
Diag aiDiagnose(String text) {
  final t = text.toLowerCase();
  bool has(List<String> w) => w.any(t.contains);
  if (has(['click', 'self', 'start nahi', 'band ho', 'battery'])) {
    return Diag(['Weak/dead battery', 'Starter relay issue'], 'battery');
  }
  if (has(['puncture', 'hawa', 'tyre', 'tire'])) {
    return Diag(['Tyre puncture', 'Valve leak'], 'puncture');
  }
  if (has(['petrol', 'fuel', 'tank', 'khatam'])) {
    return Diag(['Fuel khatam ho gaya'], 'fuel');
  }
  if (has(['dhuan', 'smoke', 'overheat', 'garam', 'engine'])) {
    return Diag(['Engine overheating', 'Coolant kam'], 'breakdown');
  }
  if (has(['accident', 'takkar', 'chot'])) return Diag(['Accident'], 'accident');
  return Diag(['Samajh nahi aaya - mechanic se dikhayein'], 'mechanic');
}

class AppState extends ChangeNotifier {
  double lat = 28.9845, lng = 77.7064;
  String label = 'Default location (Meerut)';
  Cat? cat;
  int tab = 0;
  String role = 'user', name = '';
  String providerView = 'p1';
  Diag? ai;
  String emName = '', emPhone = '';
  int _next = 1;

  final providers = <Svc>[
    Svc('p1', 'Raj Auto Service', ['puncture', 'mechanic', 'battery'], .0100, .0050, 100, rating: 4.7, n: 42),
    Svc('p2', 'Sharma Bike Care', ['puncture', 'fuel', 'mechanic'], -.0170, .0080, 80, rating: 4.5, n: 30),
    Svc('p3', 'Khan Towing', ['towing', 'breakdown', 'accident'], .0250, -.0150, 300, rating: 4.3, n: 18),
    Svc('p4', 'Power Battery House', ['battery', 'breakdown'], -.0300, -.0200, 100,
        online: false, rating: 4.1, n: 9, status: 'pending'),
  ];
  final reqs = <Req>[];

  Svc prov(String id) => providers.firstWhere((p) => p.id == id);
  double dist(Svc p, double a, double o) => km(a, o, lat + p.dLat, lng + p.dLng);

  List<Svc> nearby() {
    if (cat == null) return [];
    final l = providers
        .where((p) => p.status == 'approved' && p.online && p.cats.contains(cat!.id))
        .toList();
    l.sort((a, b) => dist(a, lat, lng).compareTo(dist(b, lat, lng)));
    return l;
  }

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  void requestHelp(Svc p) => set(() {
        final d = DateTime.now();
        reqs.insert(0, Req(_next++, cat!.id, p.id, p.fee, '${d.day}/${d.month}', lat, lng));
      });

  Future<String?> useGps() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return 'Location allow nahi hui. Default location use ho rahi hai.';
    }
    final p = await Geolocator.getCurrentPosition();
    set(() {
      lat = p.latitude;
      lng = p.longitude;
      label = 'Aapki current location';
    });
    return null;
  }
}

final app = AppState();

// ============ 4. SMALL UI HELPERS ============
Widget box(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(10)),
      child: child,
    );

Widget btn(String t, VoidCallback f, {Color c = blue}) => ElevatedButton(
      onPressed: f,
      style: ElevatedButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
    );

Widget tag(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ============ 5. APP + HOME ============
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
  runApp(const RoadResQApp());
}

class RoadResQApp extends StatelessWidget {
  const RoadResQApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RoadResQ',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(seedColor: blue),
          textTheme: GoogleFonts.barlowTextTheme(),
        ),
        home: const AuthGate(),
      );
}

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: yel,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: Text('🚗 RoadResQ', style: head(30)),
          actions: [
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () {
                app.role = 'user';
                FirebaseAuth.instance.signOut();
              },
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(6),
            child: SizedBox(height: 6, width: double.infinity, child: ColoredBox(color: ink)),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: red,
          shape: const CircleBorder(),
          onPressed: () => showDialog(context: context, builder: (_) => const SosDialog()),
          child: Text('SOS', style: head(20).copyWith(color: Colors.white)),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(children: [
                Expanded(child: app.role == 'provider' ? ProviderScreen() : UserScreen()),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ============ 6. USER SCREEN ============
class UserScreen extends StatefulWidget {
  const UserScreen({super.key});
  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  final aiCtl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final active = app.reqs.where((r) => r.status == 'pending' || r.status == 'accepted').firstOrNull;
    final done = app.reqs.where((r) => ['completed', 'cancelled', 'rejected'].contains(r.status)).toList();
    final toRate = done.where((r) => r.status == 'completed' && r.rating == null).firstOrNull;

    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), children: [
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🚨 Need Emergency Help?', style: head(26)),
        Text('📍 ${app.label}', style: const TextStyle(color: mute)),
        TextButton(
          onPressed: () async {
            final m = await app.useGps();
            if (m != null && context.mounted) toast(context, m);
          },
          child: const Text('Meri location lo'),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            for (final c in cats)
              GestureDetector(
                onTap: () => app.set(() => app.cat = c),
                child: Container(
                  decoration: BoxDecoration(
                    color: app.cat?.id == c.id ? const Color(0xFFDCE7F7) : Colors.white,
                    border: Border.all(color: app.cat?.id == c.id ? blue : line, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(c.icon, style: const TextStyle(fontSize: 26)),
                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ],
        ),
      ])),

      // AI box
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🤖 AI se poochho', style: head(22)),
        TextField(
          controller: aiCtl,
          maxLines: 2,
          decoration: const InputDecoration(
              hintText: 'Jaise: Bike start nahi ho rahi, click ki awaaz aa rahi hai',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        btn('Problem samjhao', () {
          final d = aiDiagnose(aiCtl.text);
          app.set(() {
            app.ai = d;
            app.cat = catOf(d.cat);
          });
        }),
        if (app.ai != null) ...[
          const SizedBox(height: 8),
          Text('Possible causes: ${app.ai!.cause.join(', ')}'),
          Text('Recommended service: ${catOf(app.ai!.cat).name}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const Text('AI suggestion only. Final diagnosis should be performed by a qualified mechanic.',
              style: TextStyle(fontSize: 13, color: mute)),
        ],
      ])),

      // Active request OR nearby list
      if (active != null)
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aapki request #${active.id}', style: head(22)),
          Text('${catOf(active.cat).icon} ${catOf(active.cat).name} - ${app.prov(active.pid).shop}'),
          const SizedBox(height: 6),
          Text(active.status == 'pending'
              ? '⏳ Mechanic ke jawab ka intezaar...'
              : '🟢 ${app.prov(active.pid).shop} ne accept kar li. Mechanic ${app.dist(app.prov(active.pid), active.lat, active.lng).toStringAsFixed(1)} km door hai, raaste mein hai.'),
          const SizedBox(height: 6),
          OutlinedButton(
              onPressed: () => app.set(() => active.status = 'cancelled'),
              child: const Text('Cancel request')),
        ]))
      else if (app.cat != null)
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nearby providers - ${app.cat!.name}', style: head(22)),
          Text('Estimated visiting charge: ₹${app.cat!.lo}-₹${app.cat!.hi}',
              style: const TextStyle(color: mute)),
          if (app.nearby().isEmpty) const Text('Abhi koi provider online nahi hai. Dusri category try karein.'),
          for (final p in app.nearby())
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.shop, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('📍 ${app.dist(p, app.lat, app.lng).toStringAsFixed(1)} km   ⭐ ${p.rating}   🟢 Available'),
                    Text('₹${p.fee} visiting charge · ETA ~${max(3, (app.dist(p, app.lat, app.lng) * 6).round())} min',
                        style: const TextStyle(color: mute)),
                  ]),
                ),
                btn('Request Help', () => app.requestHelp(p)),
              ]),
            ),
        ])),

      if (toRate != null) RateCard(req: toRate),

      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📜 My Services', style: head(22)),
        if (done.isEmpty) const Text('Abhi koi service nahi hui.', style: TextStyle(color: mute)),
        for (final r in done)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
            child: Text(
                '${r.when} · ${catOf(r.cat).icon} ${catOf(r.cat).name}\n${app.prov(r.pid).shop} · ${r.finalCost != null ? '₹${r.finalCost}' : '-'} · ${r.status} ${r.rating != null ? '⭐' * r.rating! : ''}'),
          ),
      ])),
    ]);
  }
}

class RateCard extends StatefulWidget {
  final Req req;
  const RateCard({super.key, required this.req});
  @override
  State<RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<RateCard> {
  int stars = 5;
  final ctl = TextEditingController();
  @override
  Widget build(BuildContext context) => box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How was your experience?', style: head(22)),
        Row(children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              onPressed: () => setState(() => stars = i),
              icon: Icon(i <= stars ? Icons.star : Icons.star_border, color: yel, size: 32),
            ),
        ]),
        TextField(
            controller: ctl,
            decoration: const InputDecoration(hintText: 'Review likhein (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        btn('Submit rating', () {
          final p = app.prov(widget.req.pid);
          app.set(() {
            widget.req.rating = stars;
            widget.req.review = ctl.text;
            p.rating = double.parse(((p.rating * p.n + stars) / (p.n + 1)).toStringAsFixed(1));
            p.n++;
          });
        }, c: ok),
      ]));
}

// ============ 7. PROVIDER SCREEN ============
class ProviderScreen extends StatelessWidget {
  const ProviderScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = app.prov(app.providerView);
    final mine = app.reqs.where((r) => r.pid == p.id).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), children: [
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Provider chuniye (demo)', style: TextStyle(color: mute)),
        DropdownButton<String>(
          isExpanded: true,
          value: app.providerView,
          items: [for (final x in app.providers) DropdownMenuItem(value: x.id, child: Text(x.shop))],
          onChanged: (v) => app.set(() => app.providerView = v!),
        ),
        Row(children: [const Text('Verification: '), tag(p.status)]),
        const SizedBox(height: 8),
        btn(p.online ? '🟢 ONLINE - Available' : '🔴 OFFLINE - Not Available',
            () => app.set(() => p.online = !p.online),
            c: p.online ? ok : red),
      ])),
      if (p.status != 'approved')
        box(const Text('Admin approval ke baad requests milengi.'))
      else if (mine.isEmpty)
        box(const Text('Abhi koi request nahi aayi.', style: TextStyle(color: mute)))
      else
        for (final r in mine) ProviderReqCard(req: r),
    ]);
  }
}

class ProviderReqCard extends StatelessWidget {
  final Req req;
  const ProviderReqCard({super.key, required this.req});
  @override
  Widget build(BuildContext context) {
    final p = app.prov(req.pid);
    final d = app.dist(p, req.lat, req.lng).toStringAsFixed(1);
    return box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('🚨 New Assistance Request #${req.id}', style: head(21)),
      Text('${catOf(req.cat).icon} ${catOf(req.cat).name} · Distance: $d km'),
      Text('Estimated visiting fee: ₹${req.visit}'),
      Align(alignment: Alignment.centerLeft, child: tag(req.status)),
      const SizedBox(height: 8),
      if (req.status == 'pending')
        Row(children: [
          btn('Accept', () => app.set(() => req.status = 'accepted'), c: ok),
          const SizedBox(width: 8),
          btn('Reject', () => app.set(() => req.status = 'rejected'), c: red),
        ]),
      if (req.status == 'accepted') CompleteJob(req: req),
    ]));
  }
}

class CompleteJob extends StatefulWidget {
  final Req req;
  const CompleteJob({super.key, required this.req});
  @override
  State<CompleteJob> createState() => _CompleteJobState();
}

class _CompleteJobState extends State<CompleteJob> {
  final ctl = TextEditingController(text: '80');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton(
          onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${widget.req.lat},${widget.req.lng}'),
              mode: LaunchMode.externalApplication),
          child: const Text('🧭 Navigate'),
        ),
        Text('Visiting ₹${widget.req.visit} + repair/extra ₹'),
        TextField(
            controller: ctl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder())),
        const SizedBox(height: 8),
        btn('Complete Job', () {
          app.set(() {
            widget.req.finalCost = widget.req.visit + (int.tryParse(ctl.text) ?? 0);
            widget.req.status = 'completed';
          });
        }, c: ok),
      ]);
}

// ============ 8. ADMIN SCREEN ============
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) {
    int c(String s) => app.reqs.where((r) => r.status == s).length;
    final earn = app.reqs.fold<int>(0, (a, r) => a + (r.finalCost ?? 0));
    final stats = {
      'Providers': '${app.providers.length}',
      'Requests': '${app.reqs.length}',
      'Completed': '${c('completed')}',
      'Pending': '${c('pending') + c('accepted')}',
      'Cancelled': '${c('cancelled') + c('rejected')}',
      'Earnings': '₹$earn',
    };
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in stats.entries)
          Container(
            width: 105,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value, style: head(30)),
              Text(e.key),
            ]),
          ),
      ]),
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Providers', style: head(22)),
        for (final p in app.providers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text('${p.shop}\n${p.status}')),
              btn('Approve', () => app.set(() => p.status = 'approved'), c: ok),
              const SizedBox(width: 6),
              btn('Suspend', () => app.set(() {
                    p.status = 'suspended';
                    p.online = false;
                  }), c: red),
            ]),
          ),
      ])),
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Requests', style: head(22)),
        if (app.reqs.isEmpty) const Text('Koi request nahi', style: TextStyle(color: mute)),
        for (final r in app.reqs)
          Text('#${r.id}  ${catOf(r.cat).name} · ${app.prov(r.pid).shop} · ${r.status}\n📍 ${r.lat.toStringAsFixed(3)}, ${r.lng.toStringAsFixed(3)}\n'),
      ])),
    ]);
  }
}

// ============ 9. SOS ============
class SosDialog extends StatefulWidget {
  const SosDialog({super.key});
  @override
  State<SosDialog> createState() => _SosDialogState();
}

class _SosDialogState extends State<SosDialog> {
  late final n = TextEditingController(text: app.emName);
  late final p = TextEditingController(text: app.emPhone);
  String out = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('🆘 SOS', style: head(28).copyWith(color: red)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Emergency type: ${app.cat?.name ?? 'Not selected'}\nLocation: ${app.lat.toStringAsFixed(4)}, ${app.lng.toStringAsFixed(4)}'),
            TextField(controller: n, decoration: const InputDecoration(hintText: 'Emergency contact ka naam')),
            TextField(
                controller: p,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: 'Emergency contact ka number')),
            if (out.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(out)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Band karo')),
          btn('Contact ko bhejo', () {
            app.emName = n.text;
            app.emPhone = p.text;
            setState(() => out = p.text.isEmpty
                ? 'Number daalein.'
                : 'Prototype: ${n.text.isEmpty ? 'Contact' : n.text} (${p.text}) ko message jaata:\n"Main emergency mein hoon. Meri location: https://maps.google.com/?q=${app.lat},${app.lng}"');
          }, c: red),
        ],
      );
}

// ============ 10. FIREBASE: REGISTER / LOGIN ============
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    if (!firebaseConfigured) return const SetupNeeded();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Loading('Load ho raha hai...');
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return ProfileLoader(user: user);
      },
    );
  }
}

class Loading extends StatelessWidget {
  final String text;
  final bool showLogout;
  const Loading(this.text, {super.key, this.showLogout = false});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(text, textAlign: TextAlign.center),
              if (showLogout)
                TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Logout')),
            ]),
          ),
        ),
      );
}

class SetupNeeded extends StatelessWidget {
  const SetupNeeded({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: yel, title: Text('🚗 RoadResQ', style: head(30))),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
              'Firebase abhi set nahi hua hai.\n\nfirebase_config.dart file mein apni 4 Firebase values daalein, phir dobara build karein.'),
        ),
      );
}

class ProfileLoader extends StatelessWidget {
  final User user;
  const ProfileLoader({super.key, required this.user});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Loading('Profile load nahi hui:\n${snap.error}', showLogout: true);
          }
          final data = snap.data?.data();
          if (data == null) return const Loading('Profile ban rahi hai...', showLogout: true);
          app.role = (data['role'] ?? 'user') as String;
          app.name = (data['name'] ?? '') as String;
          return Home();
        },
      );
}

String authMsg(String code, String? m) {
  switch (code) {
    case 'email-already-in-use':
      return 'Yeh email pehle se register hai. Login karein.';
    case 'invalid-email':
      return 'Email sahi nahi hai.';
    case 'weak-password':
      return 'Password kam se kam 6 akshar ka rakhein.';
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return 'Email ya password galat hai.';
    case 'network-request-failed':
      return 'Internet check karein.';
    default:
      return m ?? code;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isReg = false, busy = false;
  String role = 'user', err = '';
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();

  Future<void> submit() async {
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final auth = FirebaseAuth.instance;
      if (isReg) {
        if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
          throw 'Naam aur mobile number zaroori hai.';
        }
        final c = await auth.createUserWithEmailAndPassword(
            email: email.text.trim(), password: pass.text);
        await FirebaseFirestore.instance.collection('users').doc(c.user!.uid).set({
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'email': email.text.trim(),
          'role': role,
          'verification': role == 'provider' ? 'pending' : 'none',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await auth.signInWithEmailAndPassword(email: email.text.trim(), password: pass.text);
      }
    } on FirebaseAuthException catch (e) {
      err = authMsg(e.code, e.message);
    } catch (e) {
      err = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: yel,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          title: Text('🚗 RoadResQ', style: head(30)),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(6),
            child: SizedBox(height: 6, width: double.infinity, child: ColoredBox(color: ink)),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isReg ? 'Naya account banayein' : 'Login karein', style: head(26)),
                  const SizedBox(height: 8),
                  if (isReg) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'user', label: Text('Customer')),
                        ButtonSegment(value: 'provider', label: Text('Mechanic')),
                      ],
                      selected: {role},
                      onSelectionChanged: (v) => setState(() => role = v.first),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Naam', border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                    TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Mobile number', border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(
                      controller: pass,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password (6+ akshar)', border: OutlineInputBorder())),
                  if (err.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(err, style: const TextStyle(color: red, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 12),
                  busy
                      ? const Center(child: CircularProgressIndicator())
                      : btn(isReg ? 'Register' : 'Login', submit),
                  TextButton(
                    onPressed: () => setState(() {
                      isReg = !isReg;
                      err = '';
                    }),
                    child: Text(isReg ? 'Pehle se account hai? Login karein' : 'Naya account banayein'),
                  ),
                ])),
              ]),
            ),
          ),
        ),
      );
}
