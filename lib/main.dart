import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAuth.instance.signInAnonymously();

  runApp(const MyApp());
}

final db = FirebaseFirestore.instance;
const Distance geoDistance = Distance();


const LatLng kStartA = LatLng(51.4577, -2.5846); // Cabot Circus civarı
const LatLng kStartB = LatLng(51.4582, -2.5890); // Broadmead civarı

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trusted Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const RolePick(),
    );
  }
}


class RolePick extends StatelessWidget {
  const RolePick({super.key});

  @override
  Widget build(BuildContext context) {
    Widget roleBtn(String role) => SizedBox(
          width: 240,
          child: FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TrackerHome(myId: role)),
            ),
            child: Text("Continue as User $role"),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text("Trusted Tracker")),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Open two tabs/windows:", style: TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          const Text("One as User A, one as User B", style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          roleBtn("A"),
          const SizedBox(height: 10),
          roleBtn("B"),
        ]),
      ),
    );
  }
}

class TrackerHome extends StatefulWidget {
  final String myId; // "A" or "B"
  const TrackerHome({super.key, required this.myId});

  
  

  

  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome>  { 
LatLng _posFromCache(String id, Map<String, dynamic>? d) {
  // default fallback
  final start = (id == "A") ? kStartA : kStartB;
  if (d == null) return start;

  // live mode (time-based)
  final live = (d["liveMode"] == true);
  final startTs = d["liveStartTs"] as int?;
  final seed = (d["seed"] as int?) ?? (id == "A" ? 1 : 2);

  if (live && startTs != null) {
    return _livePositionFromTime(start: start, startTs: startTs, seed: seed);
  }

  // normal mode (stored lat/lng)
  final lat = (d["lat"] as num?)?.toDouble();
  final lng = (d["lng"] as num?)?.toDouble();
  if (lat == null || lng == null) return start;
  return LatLng(lat, lng);
}

LatLng _livePositionFromTime({
  required LatLng start,
  required int startTs,
  required int seed,
}) {
  final elapsedSec = ((DateTime.now().millisecondsSinceEpoch - startTs) / 1000).floor();

  // küçük adımlar (Bristol civarı)
  const stepLat = 0.00010;
  const stepLng = 0.00015;

  // deterministik yön
  final dirA = (seed % 2 == 0) ? 1 : -1;
  final dirB = (seed % 3 == 0) ? 1 : -1;

  final lat = start.latitude + dirA * stepLat * (elapsedSec % 300);
  final lng = start.longitude + dirB * stepLng * (elapsedSec % 300);
  return LatLng(lat, lng);
}

bool liveMode = false;
Timer? liveTimer;
StreamSubscription? liveModeSub;
int? liveStartTs;
int liveSeed = 1; // A=1, B=2 yapacağız
Timer? uiTicker;

Map<String, dynamic>? cacheA;
Map<String, dynamic>? cacheB;

  late final String otherId = widget.myId == "A" ? "B" : "A";

void _listenMySharingFlag() {
  
  myShareSub?.cancel();

  myShareSub = locDoc(widget.myId).snapshots().listen((snap) {
    if (!snap.exists) return;
    final d = snap.data();
    if (d == null) return;

    final flag = (d["sharing"] == true);
    

    if (!mounted) return;

    // UI state güncelle
    if (sharing != flag) {
      setState(() => sharing = flag);
    }

    // Timer yönetimi (sharing Firestore'a göre)
    if (flag) {
      shareTimer?.cancel();
      shareTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await _pushMyLocation(myMock);
      });
    } else {
      shareTimer?.cancel();
      shareTimer = null;
      
      
    }
  });
}

Future<void> _loadMyLastPosition() async {
  final snap = await locDoc(widget.myId).get();

  if (snap.exists) {
    final d = snap.data()!;
    final p = LatLng(
      (d["lat"] as num).toDouble(),
      (d["lng"] as num).toDouble(),
    );

    if (!mounted) return;
    setState(() {
      myMock = p;
      myPos = p;
      _appendTrail(myTrail, p);
    });

    // Haritayı da oraya çek
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      mapController.move(p, 17);
    });

    _log("Loaded last position from Firestore.");
  } else {
    // İlk defa açılıyorsa start konumu yaz
    await _pushMyLocation(myMock);
    _log("No saved position yet. Using start position.");
  }
}

  

  int tab = 0;

  final MapController mapController = MapController();

  bool sharing = false;
  Timer? shareTimer;
  bool autoMove = false;
Timer? autoMoveTimer;


  late LatLng myMock = widget.myId == "A" ? kStartA : kStartB;
  late LatLng myPos = myMock;
  late LatLng otherPos = otherId == "A" ? kStartA : kStartB;

  // trails (liste kalsın, ama haritada çizgi göstermeyeceğiz)
  final List<LatLng> myTrail = [];
  final List<LatLng> otherTrail = [];

  LatLng? safeCenter;
  double radiusM = 200;

  String? alertBanner;
  bool popupEnabled = true;
  final List<String> logs = [];

  StreamSubscription? subA;
  StreamSubscription? subB;
  StreamSubscription? zoneSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? myShareSub;
  
  LatLng get _initialMapCenter => widget.myId == "A" ? kStartA : kStartB;

  @override
  
  void initState() {
    super.initState();

    _loadSharingFromFirestore();
    _listenLocations();
    _listenMyZoneConfig();
    _appendTrail(myTrail, myPos);
    _syncSharingFromFirestore();
    _listenMySharingFlag();
    _loadMyLastPosition();
    _listenLiveModeFlag();
    uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
  if (!mounted) return;
  setState(() {}); // sadece redraw için
});

    
    
    
    

    

    
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1) İlk center'a küçük bir move (tile render tetikler)
      mapController.move(_initialMapCenter, 16);

      // 2) Kısa süre sonra gerçek pozisyona zıplat
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        mapController.move(myPos, 17);
      });

      // 3) Bazı makinelerde ikinci invalidate gerekiyor
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        mapController.move(myPos, 17);
      });
    });
  }

  void _syncSharingFromFirestore() {
  myShareSub?.cancel();

  myShareSub = locDoc(widget.myId).snapshots().listen((snap) {
    if (!snap.exists) return;
    final d = snap.data();
    if (d == null) return;

    final flag = (d["sharing"] == true);

    if (!mounted) return;
    if (sharing != flag) {
      setState(() => sharing = flag);
    }
  });
}


  @override
  void dispose() {
    shareTimer?.cancel();
    subA?.cancel();
    subB?.cancel();
    zoneSub?.cancel();
    super.dispose();
    autoMoveTimer?.cancel();
    myShareSub?.cancel();
    liveTimer?.cancel();
    liveModeSub?.cancel();
    uiTicker?.cancel();
  }

  DocumentReference<Map<String, dynamic>> locDoc(String id) =>
      db.collection("locations").doc(id);

  DocumentReference<Map<String, dynamic>> zoneDoc(String ownerId) =>
      db.collection("zones").doc(ownerId);

  
  Future<void> _resetDemoPositions() async {
await locDoc("A").set({
  "lat": kStartA.latitude,
  "lng": kStartA.longitude,
  "ts": DateTime.now().millisecondsSinceEpoch,
}, SetOptions(merge: true));

await locDoc("B").set({
  "lat": kStartB.latitude,
  "lng": kStartB.longitude,
  "ts": DateTime.now().millisecondsSinceEpoch,
}, SetOptions(merge: true));

    await locDoc("B").set({
      "lat": kStartB.latitude,
      "lng": kStartB.longitude,
      "ts": DateTime.now().millisecondsSinceEpoch,
      "sharing": false,
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      myMock = widget.myId == "A" ? kStartA : kStartB;
      myPos = myMock;
      otherPos = otherId == "A" ? kStartA : kStartB;

      myTrail.clear();
      otherTrail.clear();
      _appendTrail(myTrail, myPos);
      alertBanner = null;
    });

    _log("Demo positions reset to Bristol (land).");

    
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      mapController.move(myPos, 17);
    });
  }

  Future<void> _pushMyLocation(LatLng p) async {
    await locDoc(widget.myId).set({
      "lat": p.latitude,
      "lng": p.longitude,
      "ts": DateTime.now().millisecondsSinceEpoch,
      "sharing": sharing,
    }, SetOptions(merge: true));
  }

void _listenLocations() {
  subA?.cancel();
  subB?.cancel();

  subA = locDoc("A").snapshots().listen((snap) {
    if (!snap.exists) return;

    final d = snap.data();                 // Map<String,dynamic>?
    final p = _posFromCache("A", d);       // ✅ burada

    if (!mounted) return;
    setState(() {
      if (widget.myId == "A") {
        myPos = p;
        _appendTrail(myTrail, p);
      } else {
        otherPos = p;
        _appendTrail(otherTrail, p);
      }
    });

    _checkSafeZoneIfNeeded(targetId: "A", targetPos: p);
  });

  subB = locDoc("B").snapshots().listen((snap) {
    if (!snap.exists) return;

    final d = snap.data();
    final p = _posFromCache("B", d);       // ✅ burada

    if (!mounted) return;
    setState(() {
      if (widget.myId == "B") {
        myPos = p;
        _appendTrail(myTrail, p);
      } else {
        otherPos = p;
        _appendTrail(otherTrail, p);
      }
    });

    _checkSafeZoneIfNeeded(targetId: "B", targetPos: p);
  });
}

  void _appendTrail(List<LatLng> trail, LatLng p) {
    trail.add(p);
    if (trail.length > 25) trail.removeAt(0);
  }
  

  void _listenMyZoneConfig() {
    zoneSub = zoneDoc(widget.myId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final d = snap.data()!;
      if (d["target"] != otherId) return;
      if (!mounted) return;
      setState(() {
        safeCenter = LatLng((d["lat"] as num).toDouble(), (d["lng"] as num).toDouble());
        radiusM = (d["radiusM"] as num).toDouble();
      });
    });
  }
  
  void _listenLiveModeFlag() {
  liveModeSub = locDoc(widget.myId).snapshots().listen((snap) {
    if (!snap.exists) return;
    final d = snap.data();
    if (d == null) return;

    final flag = (d["liveMode"] == true);

    if (!mounted) return;

    // UI state zaten aynıysa dokunma
    if (liveMode == flag) return;

    setState(() => liveMode = flag);

    // Firestore state'e göre timer'ı yönet
    if (flag) {
      _startLiveModeTimer();
    } else {
      _stopLiveModeTimer();
    }
  });
}
  

  Future<void> _saveMyZoneFromCurrentOther() async {
    final center = otherPos;
    await zoneDoc(widget.myId).set({
      "target": otherId,
      "lat": center.latitude,
      "lng": center.longitude,
      "radiusM": radiusM,
      "ts": DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));

    _log("Safe zone set for $otherId (radius ${radiusM.toInt()}m)");
  }

  void _checkSafeZoneIfNeeded({required String targetId, required LatLng targetPos}) {
    if (targetId != otherId) return;
    if (safeCenter == null) return;

    final d = geoDistance.as(LengthUnit.Meter, safeCenter!, targetPos);
    final outside = d > radiusM;

    if (outside) {
      _raiseAlert("$otherId left safe zone (${d.toInt()}m > ${radiusM.toInt()}m)");
    } else {
      if (alertBanner != null) {
        setState(() => alertBanner = null);
        _log("$otherId back inside safe zone (${d.toInt()}m)");
      }
    }
  }

  void _raiseAlert(String msg) {
    if (alertBanner == msg) return;
    setState(() => alertBanner = msg);
    _log("ALERT: $msg");

    if (popupEnabled) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Safe Zone Alert"),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
          ],
        ),
      );
    }
  }

  void _log(String msg) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    if (!mounted) return;
    setState(() {
      logs.insert(0, "[$stamp] $msg");
      if (logs.length > 60) logs.removeLast();
    });
  }
  
  Future<void> _loadSharingFromFirestore() async {
  final snap = await locDoc(widget.myId).get();
  if (!snap.exists) return;

  final d = snap.data();
  if (d == null) return;

  final flag = (d["sharing"] == true);

  if (!mounted) return;
  setState(() => sharing = flag);

  // Eğer daha önce ON ise, geri girince timer tekrar başlasın
  if (sharing) {
    shareTimer?.cancel();
    shareTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pushMyLocation(myMock);
    });
  } else {
    shareTimer?.cancel();
  }
}



void _toggleSharing() async {
  setState(() => sharing = !sharing);

  // her durumda Firestore’a "sharing" flag’ini yaz
  await locDoc(widget.myId).set({
    "sharing": sharing,
    "ts": DateTime.now().millisecondsSinceEpoch,
  }, SetOptions(merge: true));

  if (sharing) {
    _log("Sharing ON");
    shareTimer?.cancel();
    shareTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pushMyLocation(myMock);
    });
  } else {
    _log("Sharing OFF");
    shareTimer?.cancel();
    await _pushMyLocation(myMock);
  }
}



void _startLiveModeTimer() {
  liveTimer?.cancel();

  // 2 saniyede bir küçük random adım (demo GPS)
  liveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
    // küçük hareket
    const stepLat = 0.00015;
    const stepLng = 0.00015;

    final t = DateTime.now().second;
    final dLat = (t % 2 == 0) ? stepLat : -stepLat;
    final dLng = (t % 3 == 0) ? stepLng : -stepLng;

    _moveMyMock(dLat, dLng); // zaten sende var
  });
}

void _stopLiveModeTimer() {
  liveTimer?.cancel();
  liveTimer = null;
}

void _startLiveMode() {
  liveTimer?.cancel();

  // eğer ilk kez başlıyorsa zaman damgası koy
  liveStartTs ??= DateTime.now().millisecondsSinceEpoch;

  liveTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
    final p = _livePositionFromTime(
      start: widget.myId == "A" ? kStartA : kStartB,
      startTs: liveStartTs!,
      seed: liveSeed,
    );

    // ekranda hareketi gör
    setState(() {
      myMock = p;
      myPos = p;
      _appendTrail(myTrail, p);
    });

    // firestore’a bas (diğer kullanıcı görsün)
    if (sharing || liveMode) {
      await _pushMyLocation(p);
    }
  });
}

void _stopLiveMode() {
  liveTimer?.cancel();
  liveTimer = null;
}
  

  void _startAutoMove() {
  autoMoveTimer?.cancel();

  autoMoveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
    // küçük adım
    const stepLat = 0.00015;
    const stepLng = 0.00015;

    final t = DateTime.now().second;
    final dLat = (t % 2 == 0) ? stepLat : -stepLat;
    final dLng = (t % 3 == 0) ? stepLng : -stepLng;

    _moveMyMock(dLat, dLng);
  });
}

void _stopAutoMove() {
  autoMoveTimer?.cancel();
  autoMoveTimer = null;
}

  

void _moveMyMock(double dLat, double dLng) {
  setState(() {
    myMock = LatLng(myMock.latitude + dLat, myMock.longitude + dLng);
    myPos = myMock;
    _appendTrail(myTrail, myMock);
  });

  // Sharing OFF olsa bile: "last known location" gibi kaydet
  _pushMyLocation(myMock);

  // Sharing ON ise zaten timer da güncelleyecek, ama bu da sorun değil.
}

  
  void _jumpTo(LatLng p) {
    mapController.move(p, 17);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      mapController.move(p, 17);
    });
  }

  String _agoFromTs(int? ts) {
    if (ts == null) return "-";
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    final s = (diff / 1000).floor();
    if (s < 60) return "${s}s ago";
    final m = (s / 60).floor();
    return "${m}m ago";
  }

  Widget _statusCard(String id) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: locDoc(id).snapshots(),
      builder: (context, snap) {
        final exists = snap.hasData && snap.data!.exists;
        final data = exists ? snap.data!.data()! : null;

        final sharingFlag = (data?["sharing"] == true);
        final ts = data?["ts"] as int?;
        final subtitle =
            exists ? "sharing: ${sharingFlag ? "ON" : "OFF"} • last: ${_agoFromTs(ts)}" : "no data yet";

return Card(
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(id == widget.myId ? Icons.person : Icons.person_pin_circle),
            const SizedBox(width: 8),
            Text("User $id", style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (id == widget.myId) Chip(label: Text(sharing ? "Sharing ON" : "Sharing OFF")),
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitle),
      ],
    ),
  ),
);
      },
    );
  }

  Widget _mapTab() {
    return Column(
      children: [
        if (alertBanner != null)
          MaterialBanner(
            content: Text(alertBanner!),
            leading: const Icon(Icons.warning_amber),
            actions: [
              TextButton(onPressed: () => setState(() => alertBanner = null), child: const Text("Dismiss"))
              
            ],
          ),
        Padding(
  padding: const EdgeInsets.all(12),
  child: LayoutBuilder(
    builder: (context, c) {
      final isNarrow = c.maxWidth < 720; // telefon/dar ekran
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: isNarrow ? c.maxWidth : (c.maxWidth - 12) / 2,
            child: _statusCard(widget.myId),
          ),
          SizedBox(
            width: isNarrow ? c.maxWidth : (c.maxWidth - 12) / 2,
            child: _statusCard(otherId),
          ),
        ],
      );
    },
  ),
),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilledButton.tonal(
                onPressed: () => _jumpTo(myPos),
                child: Text("Jump to ${widget.myId}"),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: () => _jumpTo(otherPos),
                child: Text("Jump to $otherId"),
              ),
              const Spacer(),
              IconButton(
                tooltip: "Reset demo positions",
                onPressed: _resetDemoPositions,
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                tooltip: "Toggle popup alerts",
                onPressed: () => setState(() => popupEnabled = !popupEnabled),
                icon: Icon(popupEnabled ? Icons.notifications_active : Icons.notifications_off),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FlutterMap(
            mapController: mapController,
            
            options: MapOptions(initialCenter: _initialMapCenter, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.example.tracker_demo",
              ),

              if (safeCenter != null)
  CircleLayer(
    circles: [
      CircleMarker(
        point: safeCenter!,
        radius: radiusM, // metre cinsinden
        useRadiusInMeter: true,
        color: const Color.fromRGBO(33, 150, 243, 0.15), // mavi, %15
borderStrokeWidth: 2,
borderColor: const Color.fromARGB(179, 33, 150, 243), // mavi, %70
      ),
    ],
  ),

              MarkerLayer(markers: [
                Marker(
                  point: myPos,
                  width: 44,
                  height: 44,
                  child: const Icon(Icons.person_pin_circle, size: 44),
                ),
                Marker(
                  point: otherPos,
                  width: 44,
                  height: 44,
                  child: const Icon(Icons.location_on, size: 44),
                ),
                
                if (safeCenter != null)
                  Marker(
                    point: safeCenter!,
                    width: 34,
                    height: 34,
                    child: const Icon(Icons.shield, size: 34),
                  ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  
  

  Widget _controlsTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Live sharing", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(onPressed: _toggleSharing, child: Text(sharing ? "Stop sharing" : "Start sharing")),
                const SizedBox(width: 12),
                Text("User ${widget.myId}"),
              ]),
              const SizedBox(height: 10),
              Text("Current: ${myMock.latitude.toStringAsFixed(5)}, ${myMock.longitude.toStringAsFixed(5)}"),
              const SizedBox(height: 10),

SwitchListTile(
  contentPadding: EdgeInsets.zero,
  title: const Text("Live Mode (Simulated GPS)"),
  subtitle: const Text("ON = continuous movement + sharing"),
  value: liveMode,
onChanged: (v) async {
await locDoc(widget.myId).set({
  "liveMode": v,
  "liveStartTs": DateTime.now().millisecondsSinceEpoch,
  "liveSeed": DateTime.now().millisecondsSinceEpoch % 100000, // random route seed
}, SetOptions(merge: true));
if (v) {
  _startLiveMode();
} else {
  _stopLiveMode();
  final now = DateTime.now().millisecondsSinceEpoch;

await locDoc(widget.myId).set({
  "liveMode": v,
  if (v) "liveStartTs": now,
  "seed": widget.myId == "A" ? 1 : 2,
}, SetOptions(merge: true));
}
},
),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Manual movement (User ${widget.myId})",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
  children: [
    FilledButton.tonal(
      onPressed: () {
        setState(() => autoMove = !autoMove);

        if (autoMove) {
          _startAutoMove();
          _log("Auto-move ON");
        } else {
          _stopAutoMove();
          _log("Auto-move OFF");
        }
      },
      child: Text(autoMove ? "Stop Auto-Move" : "Start Auto-Move"),
    ),
    const SizedBox(width: 12),
    Text(autoMove ? "Running..." : "Idle"),
  ],
),
const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.tonal(onPressed: () => _moveMyMock(0.001, 0), child: const Text("North")),
                FilledButton.tonal(onPressed: () => _moveMyMock(-0.001, 0), child: const Text("South")),
                FilledButton.tonal(onPressed: () => _moveMyMock(0, 0.002), child: const Text("East")),
                FilledButton.tonal(onPressed: () => _moveMyMock(0, -0.002), child: const Text("West")),
              ]),
              const SizedBox(height: 8),
              const Text("Keep sharing ON to broadcast updates in real time."),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Safe zone for $otherId", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(onPressed: _saveMyZoneFromCurrentOther, child: const Text("Set center to other user")),
                const SizedBox(width: 12),
                Text("Radius: ${radiusM.toInt()}m"),
              ]),
              Slider(
                value: radiusM,
                min: 50,
                max: 500,
                divisions: 9,
                label: "${radiusM.toInt()}m",
                onChanged: (v) => setState(() => radiusM = v),
                onChangeEnd: (_) async {
                  if (safeCenter != null) {
                    await zoneDoc(widget.myId).set({
                      "target": otherId,
                      "radiusM": radiusM,
                      "ts": DateTime.now().millisecondsSinceEpoch,
                    }, SetOptions(merge: true));
                    _log("Updated radius for $otherId to ${radiusM.toInt()}m");
                  }
                },
              ),
              const SizedBox(height: 8),
              const Text("Alert triggers when the other user exits the zone."),
            ]),
          ),
        ),
      ],
    );
  }


  Widget _logsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: logs.length,
      itemBuilder: (_, i) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(logs[i]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_mapTab(), _controlsTab(), _logsTab()];

    return Scaffold(
      appBar: AppBar(title: Text("Trusted Tracker • User ${widget.myId}")),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: "Map"),
          NavigationDestination(icon: Icon(Icons.tune), label: "Controls"),
          NavigationDestination(icon: Icon(Icons.list_alt), label: "Logs"),
        ],
      ),
    );
  }
}


