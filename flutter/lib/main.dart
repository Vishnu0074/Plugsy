import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';

const apiBase = String.fromEnvironment('PLUGSY_API_BASE_URL', defaultValue: 'http://10.0.2.2:8000/api');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => PlugsyState(), child: const PlugsyApp()));
}

class PlugsyState extends ChangeNotifier {
  String? access;
  bool loading = true;
  List<dynamic> chargers = [];
  String? error;
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    access = p.getString('access');
    loading = false;
    notifyListeners();
    if (access != null) { await loadChargers(); }
  }
  PlugsyState() { init(); }
  Future<dynamic> request(String path, {String method = 'GET', Map<String,dynamic>? body, bool auth = true}) async {
    final headers = <String,String>{'Content-Type':'application/json'};
    if (auth && access != null) headers['Authorization'] = 'Bearer $access';
    final uri = Uri.parse('$apiBase$path');
    late http.Response res;
    if (method == 'POST') {
      res = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
    } else { res = await http.get(uri, headers: headers); }
    dynamic data;
    try { data = jsonDecode(res.body); } catch (_) { data = {'detail': res.body}; }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = data is Map ? (data['detail'] ?? data.values.first) : data;
      throw Exception(detail.toString());
    }
    return data;
  }
  Future<void> saveTokens(Map<String,dynamic> data) async {
    access = data['access']?.toString();
    final p = await SharedPreferences.getInstance();
    if (access != null) await p.setString('access', access!);
    notifyListeners();
    await loadChargers();
  }
  Future<void> auth({required bool register, required String identity, required String password, String email = '', bool host = false}) async {
    final data = await request(register ? '/auth/register/' : '/auth/login/', method:'POST', auth:false,
      body: register ? {'email':email,'username':identity,'password':password,'wants_to_host':host} : {'username':identity,'password':password});
    await saveTokens(data as Map<String,dynamic>);
  }
  Future<void> loadChargers({double? lat, double? lng}) async {
    try {
      error = null;
      final q = lat != null && lng != null ? '?lat=$lat&lng=$lng' : '';
      final d = await request('/chargers/$q');
      chargers = d is List ? d : (d['results'] as List? ?? []);
    } catch(e) { error = e.toString(); }
    notifyListeners();
  }
  Future<List<dynamic>> loadNotifications() async {
    final data = await request('/notifications/');
    return data is List ? data : (data['results'] as List? ?? []);
  }
  Future<void> logout() async {
    access = null; chargers = [];
    final p = await SharedPreferences.getInstance(); await p.remove('access'); notifyListeners();
  }
}

class PlugsyApp extends StatelessWidget {
  const PlugsyApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title:'Plugsy', debugShowCheckedModeBanner:false,
    theme: ThemeData(useMaterial3:true, colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFFB7F36B)), scaffoldBackgroundColor:const Color(0xFFF7F8F5)),
    home: Consumer<PlugsyState>(builder:(context,s,_) => s.loading ? const Scaffold(body:Center(child:CircularProgressIndicator())) : s.access == null ? const AuthPage() : const HomePage()),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override State<AuthPage> createState()=>_AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
  final form=GlobalKey<FormState>();
  final identity=TextEditingController(), email=TextEditingController(), password=TextEditingController();
  bool register=false, host=false, busy=false, obscure=true;
  @override void dispose(){identity.dispose();email.dispose();password.dispose();super.dispose();}
  Future<void> submit() async {
    if(!form.currentState!.validate()) return;
    setState(()=>busy=true);
    try {
      await context.read<PlugsyState>().auth(register:register,identity:identity.text.trim(),password:password.text,email:email.text.trim(),host:host);
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ','')))); }
    finally { if(mounted) setState(()=>busy=false); }
  }
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:460),child:Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Container(width:72,height:72,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFFB7F36B),borderRadius:BorderRadius.circular(22)),child:const Icon(Icons.bolt,size:42)),
    const SizedBox(height:24),const Text('Plugsy',style:TextStyle(fontSize:36,fontWeight:FontWeight.w900)),
    Text(register?'Join the community-powered charging network.':'Find a charge. Share the power.',style:const TextStyle(color:Colors.black54)),
    const SizedBox(height:26),
    if(register) ...[TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email address',prefixIcon:Icon(Icons.mail_outline)),validator:(v)=>v==null||!v.contains('@')?'Enter a valid email':null),const SizedBox(height:12)],
    TextFormField(controller:identity,decoration:InputDecoration(labelText:register?'Choose a username':'Username or email',prefixIcon:const Icon(Icons.person_outline)),validator:(v)=>v==null||v.trim().length<3?'Enter at least 3 characters':null),
    const SizedBox(height:12),
    TextFormField(controller:password,obscureText:obscure,decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility:Icons.visibility_off))),validator:(v)=>v==null||v.length<8?'Use at least 8 characters':null),
    if(register) ...[const SizedBox(height:16),Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:SwitchListTile(value:host,onChanged:(v)=>setState(()=>host=v),title:const Text('I have a charger to share',style:TextStyle(fontWeight:FontWeight.bold)),subtitle:const Text('Let nearby EV drivers book it and earn from charging.'),contentPadding:EdgeInsets.zero))],
    const SizedBox(height:20),FilledButton(onPressed:busy?null:submit,child:Padding(padding:const EdgeInsets.all(14),child:Text(busy?'Please wait…':register?'Create account':'Log in'))),
    TextButton(onPressed:()=>setState(()=>register=!register),child:Text(register?'Already registered? Log in':'New to Plugsy? Create an account')),
  ])))))));
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab=0; List<dynamic> bookings=[]; bool busy=false; LatLng? userPoint;
  Future<void> nearby() async {
    double? lat,lng;
    try {
      if(await Geolocator.isLocationServiceEnabled()){
        var p=await Geolocator.checkPermission();
        if(p==LocationPermission.denied)p=await Geolocator.requestPermission();
        if(p==LocationPermission.always||p==LocationPermission.whileInUse){final pos=await Geolocator.getCurrentPosition();lat=pos.latitude;lng=pos.longitude;userPoint=LatLng(pos.latitude,pos.longitude);}
      }
    }catch(_){}
    if(mounted) await context.read<PlugsyState>().loadChargers(lat:lat,lng:lng);
  }
  Future<void> loadBookings() async {
    setState(()=>busy=true);
    try {
      final d=await context.read<PlugsyState>().request('/bookings/');
      bookings=d is List?d:(d['results'] as List? ?? []);
    } catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>nearby());}
  Future<void> markPaid(dynamic booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm payment received?'),
        content: Text('Mark ₹${booking['total_amount']} as paid for this completed session? Only do this after receiving the money outside the app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm received')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context.read<PlugsyState>().request('/bookings/${booking['id']}/mark-paid/', method: 'POST');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment marked as received.')));
        await loadBookings();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
  Future<void> markStarted(dynamic booking) async {
    try { await context.read<PlugsyState>().request('/bookings/${booking['id']}/start/',method:'POST'); await loadBookings(); }
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  Future<void> completeSession(dynamic booking) async {
    final input=TextEditingController();
    final kwh=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Complete charging session'),content:TextField(controller:input,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Measured energy (kWh)',hintText:'e.g. 12.5')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,input.text.trim()),child:const Text('Complete'))]));
    if(kwh==null){input.dispose();return;}
    try { await context.read<PlugsyState>().request('/bookings/${booking['id']}/complete/',method:'POST',body:{'actual_kwh':double.parse(kwh)}); await loadBookings(); }
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{input.dispose();}
  }
  Future<void> leaveReview(dynamic booking) async {
    int rating=5; final comment=TextEditingController();
    final result=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(title:const Text('Rate your charging experience'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<int>(value:rating,decoration:const InputDecoration(labelText:'Rating'),items:[5,4,3,2,1].map((v)=>DropdownMenuItem(value:v,child:Text('$v stars'))).toList(),onChanged:(v)=>setDialog(()=>rating=v??5)),const SizedBox(height:12),TextField(controller:comment,maxLines:3,decoration:const InputDecoration(labelText:'Review (optional)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Submit review'))])));
    if(result!=true){comment.dispose();return;}
    try { await context.read<PlugsyState>().request('/reviews/',method:'POST',body:{'charger':booking['charger'],'booking':booking['id'],'rating':rating,'comment':comment.text.trim()}); if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Review submitted. Thank you!')));await loadBookings();} }
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{comment.dispose();}
  }
  Future<void> showNotifications() async {
    try {
      final items=await context.read<PlugsyState>().loadNotifications();
      if(!mounted)return;
      showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(16),children:[const Text('Notifications',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),if(items.isEmpty)const Text('No notifications yet.'),...items.map((n)=>ListTile(leading:Icon(n['is_read']==true?Icons.notifications_none:Icons.notifications_active),title:Text('${n['title']}'),subtitle:Text('${n['body']}'),onTap:(){context.read<PlugsyState>().request('/notifications/${n['id']}/read/',method:'POST').catchError((_)=>{});}))])));
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Plugsy',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900)),actions:[IconButton(tooltip:'Notifications',onPressed:showNotifications,icon:const Icon(Icons.notifications_outlined)),IconButton(onPressed:()=>context.read<PlugsyState>().logout(),icon:const Icon(Icons.logout))]),
    body:IndexedStack(index:tab,children:[discover(),requests()]),
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v){setState(()=>tab=v);if(v==1)loadBookings();},destinations:const[NavigationDestination(icon:Icon(Icons.explore_outlined),label:'Discover'),NavigationDestination(icon:Icon(Icons.inbox_outlined),label:'Requests')]),
    floatingActionButton:tab==0?FloatingActionButton.extended(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const HostPage())).then((v){if(v==true)nearby();}),icon:const Icon(Icons.add),label:const Text('List a charger')):null,
  );
  Widget discover()=>Consumer<PlugsyState>(builder:(context,s,_)=>RefreshIndicator(onRefresh:nearby,child:ListView(padding:const EdgeInsets.all(16),children:[
    Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:const Color(0xFF17231A),borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Low battery?',style:TextStyle(color:Color(0xFFB7F36B),fontSize:26,fontWeight:FontWeight.w900)),SizedBox(height:6),Text('Find a nearby charger shared by the community.',style:TextStyle(color:Colors.white70))])),
    const SizedBox(height:16),Row(children:[const Expanded(child:Text('Chargers near you',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),IconButton(onPressed:nearby,icon:const Icon(Icons.refresh))]),
    OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ChargerMap(chargers:s.chargers, initial:userPoint))),icon:const Icon(Icons.map_outlined),label:const Text('View on map')),
    if(s.error!=null)Text('API error: ${s.error}'),
    if(s.chargers.isEmpty&&!s.loading)const Padding(padding:EdgeInsets.all(18),child:Text('No published chargers found yet. Try again or become the first host in your area.')),
    if(s.loading)const Center(child:CircularProgressIndicator()),
    ...s.chargers.map((c)=>Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFEAF8D9),child:Icon(Icons.ev_station,color:Colors.black)),title:Text('${c['title']}',style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${c['connector_type']} · ${c['power_kw']} kW · ★ ${c['average_rating']??0} (${c['review_count']??0})'),trailing:Text('₹${c['price_per_kwh']}\n/kWh',textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.bold)),onTap:()=>requestCharge(c))),
  ])));
  Future<void> requestCharge(dynamic c) async {
    final estimate=TextEditingController(text:'10');
    final kwh=await showModalBottomSheet<String>(context:context,isScrollControlled:true,builder:(ctx)=>Padding(padding:EdgeInsets.only(left:24,right:24,top:24,bottom:MediaQuery.of(ctx).viewInsets.bottom+24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${c['title']}',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:8),Text('₹${c['price_per_kwh']} / kWh · ${c['connector_type']}'),
      const SizedBox(height:12),const Text('Choose an estimated energy amount. The host must accept the request. You will settle the final amount with the host outside Plugsy after the session.'),
      const SizedBox(height:12),TextField(controller:estimate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Estimated energy (kWh)')),
      const SizedBox(height:12),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>Navigator.pop(ctx,estimate.text.trim()),child:const Text('Send booking request'))),
    ])));
    if(kwh==null){estimate.dispose();return;}
    try{
      final amount=double.parse(kwh);
      if(amount<0.1||amount>1000)throw Exception('Enter estimated energy between 0.1 and 1000 kWh.');
      final d=await context.read<PlugsyState>().request('/bookings/',method:'POST',body:{'charger':c['id'],'estimated_kwh':amount});
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Request sent: ${d['status']??'pending'}')));setState(()=>tab=1);await loadBookings();}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{estimate.dispose();}
  }
  Widget requests()=>RefreshIndicator(onRefresh:loadBookings,child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Booking requests & sessions',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
    const SizedBox(height:8),
    if(busy)const Center(child:CircularProgressIndicator()),
    if(!busy&&bookings.isEmpty)const Text('Booking requests and sessions will appear here. Pull to refresh.'),
    ...bookings.map((b){
      final isHost=b['is_host']==true;
      final state=(b['status']??'pending').toString();
      final started=b['session_started_at']!=null;
      final paid=b['payment_status']=='paid';
      final hasReview=b['has_review']==true;
      Widget? action;
      if(isHost&&state=='pending'){
        action=PopupMenuButton<bool>(tooltip:'Respond',onSelected:(accept)=>respond(b['id'],accept),itemBuilder:(_)=>const[PopupMenuItem(value:true,child:Text('Accept request')),PopupMenuItem(value:false,child:Text('Decline request'))]);
      } else if(isHost&&state=='accepted'&&!started){
        action=IconButton(tooltip:'Start charging session',onPressed:()=>markStarted(b),icon:const Icon(Icons.play_circle_outline));
      } else if(isHost&&state=='accepted'&&started){
        action=IconButton(tooltip:'Complete session',onPressed:()=>completeSession(b),icon:const Icon(Icons.check_circle_outline));
      } else if(isHost&&state=='completed'&&!paid){
        action=FilledButton(onPressed:()=>markPaid(b),child:const Text('Mark as paid'));
      } else if(!isHost&&state=='completed'&&!paid){
        action=const Text('Awaiting host confirmation');
      } else if(!isHost&&state=='completed'&&paid&&!hasReview){
        action=TextButton(onPressed:()=>leaveReview(b),child:const Text('Review'));
      } else if(!isHost&&state=='completed'&&paid&&hasReview){
        action=const Icon(Icons.verified,color:Colors.green);
      }
      return Card(margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.ev_station,size:28),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${b['charger_title']??'Charger'}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
          Text('Booking #${b['id']} · ${isHost?'Driver':'Host'}: @${isHost?(b['driver_username']??'driver'):(b['charger_host']??'host')}'),
        ])),Text(state.toUpperCase(),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800))]),
        const SizedBox(height:8),
        Text('Estimated: ${b['estimated_kwh']??'—'} kWh · Actual: ${b['actual_kwh']??'pending'} kWh'),
        if(b['total_amount']!=null)Text('Final total: ₹${b['total_amount']} · Payment: ${b['payment_status']}'),
        if(state=='accepted'&&!started)const Text('Host can start the session after the driver arrives.',style:TextStyle(color:Colors.black54)),
        if(state=='accepted'&&started)const Text('Session started. Host records measured kWh when charging ends.',style:TextStyle(color:Colors.black54)),
        if(state=='completed'&&!paid)const Text('Payment is handled outside Plugsy. The host marks it as paid after receiving the money.',style:TextStyle(color:Colors.black54)),
        if(action!=null)Align(alignment:Alignment.centerRight,child:action),
      ])));
    }),
  ]));
  Future<void> respond(dynamic id,bool accept)async{try{await context.read<PlugsyState>().request('/bookings/$id/respond/',method:'POST',body:{'accept':accept});await loadBookings();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
}

class ChargerMap extends StatelessWidget {
  const ChargerMap({super.key, required this.chargers, this.initial});
  final List<dynamic> chargers;
  final LatLng? initial;

  @override
  Widget build(BuildContext context) {
    final fallback = chargers.isNotEmpty
        ? LatLng(
            double.tryParse(chargers.first['latitude'].toString()) ?? 9.9312,
            double.tryParse(chargers.first['longitude'].toString()) ?? 76.2673,
          )
        : const LatLng(9.9312, 76.2673);
    return Scaffold(
      appBar: AppBar(title: const Text('Chargers nearby')),
      body: LeafletMapView(
        initial: initial ?? fallback,
        chargers: chargers,
        onChargerTap: (charger) {
          showModalBottomSheet(
            context: context,
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${charger['title']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('₹${charger['price_per_kwh']} / kWh'),
                    Text('${charger['connector_type']} · ${charger['power_kw']} kW'),
                    Text('★ ${charger['average_rating'] ?? 0} (${charger['review_count'] ?? 0} reviews)'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Actual Leaflet.js map in a WebView, using OpenStreetMap tiles.
class LeafletMapView extends StatefulWidget {
  const LeafletMapView({
    super.key,
    required this.initial,
    this.chargers = const [],
    this.pickMode = false,
    this.onPointSelected,
    this.onChargerTap,
  });

  final LatLng initial;
  final List<dynamic> chargers;
  final bool pickMode;
  final ValueChanged<LatLng>? onPointSelected;
  final ValueChanged<dynamic>? onChargerTap;

  @override
  State<LeafletMapView> createState() => _LeafletMapViewState();
}

class _LeafletMapViewState extends State<LeafletMapView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LeafletBridge',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            if (data['type'] == 'pick') {
              widget.onPointSelected?.call(
                LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()),
              );
            } else if (data['type'] == 'charger') {
              final index = data['index'] as int;
              if (index >= 0 && index < widget.chargers.length) {
                widget.onChargerTap?.call(widget.chargers[index]);
              }
            }
          } catch (_) {}
        },
      )
      ..loadHtmlString(_buildLeafletHtml());
  }

  String _buildLeafletHtml() {
    final chargerData = widget.chargers.map((charger) => {
      'lat': double.tryParse(charger['latitude'].toString()) ?? 0,
      'lng': double.tryParse(charger['longitude'].toString()) ?? 0,
      'title': charger['title']?.toString() ?? 'Charger',
      'price': charger['price_per_kwh']?.toString() ?? '',
      'connector': charger['connector_type']?.toString() ?? '',
    }).toList();
    final chargersJson = jsonEncode(chargerData);
    final initialLat = widget.initial.latitude;
    final initialLng = widget.initial.longitude;
    final pickMode = widget.pickMode ? 'true' : 'false';

    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
html, body, #map { height:100%; width:100%; margin:0; padding:0; }
.leaflet-container { font-family: Arial, sans-serif; }
.pick-hint { position:absolute; z-index:1000; top:12px; left:50%; transform:translateX(-50%); background:#17231A; color:#fff; padding:9px 14px; border-radius:18px; white-space:nowrap; font-size:13px; box-shadow:0 2px 8px #0003; }
</style>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
</head>
<body>
<div id="map"></div>
${widget.pickMode ? '<div class="pick-hint">Tap the map to place your charger pin</div>' : ''}
<script>
const pickMode = $pickMode;
const chargers = $chargersJson;
const map = L.map('map', { zoomControl: true }).setView([$initialLat, $initialLng], ${widget.pickMode ? 15 : 12});
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);
let selectedMarker = null;
function setSelectedPoint(lat, lng) {
  if (selectedMarker) map.removeLayer(selectedMarker);
  selectedMarker = L.circleMarker([lat, lng], {
    radius: 10, color: '#ffffff', weight: 3, fillColor: '#e53935', fillOpacity: 1
  }).addTo(map);
}
if (pickMode) {
  setSelectedPoint($initialLat, $initialLng);
  map.on('click', function(e) {
    setSelectedPoint(e.latlng.lat, e.latlng.lng);
    LeafletBridge.postMessage(JSON.stringify({type:'pick', lat:e.latlng.lat, lng:e.latlng.lng}));
  });
} else {
  chargers.forEach(function(charger, index) {
    const marker = L.circleMarker([charger.lat, charger.lng], {
      radius: 9, color: '#ffffff', weight: 2, fillColor: '#39834b', fillOpacity: 1
    }).addTo(map);
    marker.bindPopup('<strong>' + String(charger.title).replace(/[&<>"]/g, '') + '</strong><br>₹' + charger.price + ' / kWh<br>' + String(charger.connector).replace(/[&<>"]/g, ''));
    marker.on('click', function() {
      LeafletBridge.postMessage(JSON.stringify({type:'charger', index:index}));
    });
  });
}
setTimeout(function(){ map.invalidateSize(); }, 250);
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

class HostPage extends StatefulWidget { const HostPage({super.key}); @override State<HostPage> createState()=>_HostPageState(); }
class _HostPageState extends State<HostPage>{
 final form=GlobalKey<FormState>();final title=TextEditingController(text:'Home EV Charger'),price=TextEditingController(text:'12'),power=TextEditingController(text:'7.4'),address=TextEditingController();
 final connectors=['Type 2','CCS2','CHAdeMO','Bharat AC-001','Bharat DC-001','3-pin socket (verification required)'];
 String connector='Type 2';LatLng? point;bool safety=false,available=true,busy=false;
 @override void dispose(){title.dispose();price.dispose();power.dispose();address.dispose();super.dispose();}
 Future<void> locate()async{try{if(!await Geolocator.isLocationServiceEnabled())throw Exception('Enable location services.');var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();if(p==LocationPermission.denied||p==LocationPermission.deniedForever)throw Exception('Location permission is needed.');final pos=await Geolocator.getCurrentPosition();setState(()=>point=LatLng(pos.latitude,pos.longitude));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
 Future<void> publish()async{if(!form.currentState!.validate())return;if(point==null||!safety){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Select a location and confirm charger safety.')));return;}setState(()=>busy=true);try{await context.read<PlugsyState>().request('/chargers/',method:'POST',body:{'title':title.text.trim(),'latitude':point!.latitude,'longitude':point!.longitude,'price_per_kwh':double.parse(price.text),'power_kw':double.parse(power.text),'connector_type':connector,'approximate_address':address.text.trim(),'is_available':available,'is_published':true,'safety_confirmed':true});if(mounted)Navigator.pop(context,true);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}finally{if(mounted)setState(()=>busy=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('List your charger')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(20),children:[
 const Text('Make your charger available to nearby EV drivers.',style:TextStyle(color:Colors.black54)),const SizedBox(height:16),
 TextFormField(controller:title,decoration:const InputDecoration(labelText:'Charger name'),validator:(v)=>v==null||v.trim().isEmpty?'Required':null),const SizedBox(height:12),
 DropdownButtonFormField<String>(value:connector,decoration:const InputDecoration(labelText:'Connector type'),items:connectors.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>connector=v??connector)),const SizedBox(height:12),
 TextFormField(controller:power,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Charger power (kW)'),validator:(v)=>double.tryParse(v??'')==null||double.parse(v!)<=0?'Enter valid kW':null),const SizedBox(height:12),
 TextFormField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Your price per kWh (₹)'),validator:(v)=>double.tryParse(v??'')==null||double.parse(v!)<=0?'Enter a valid price':null),const SizedBox(height:8),
 const Text('State electricity tariffs can be displayed as a reference after official tariff data is configured. This field is your own rental price, not a verified live utility tariff.',style:TextStyle(color:Colors.black54,fontSize:12)),const SizedBox(height:12),
 TextFormField(controller:address,decoration:const InputDecoration(labelText:'Area / directions (public-safe)')),
 const SizedBox(height:12),OutlinedButton.icon(onPressed:locate,icon:const Icon(Icons.my_location),label:const Text('Use current location')),
 OutlinedButton.icon(onPressed:()async{final result=await Navigator.push<LatLng>(context,MaterialPageRoute(builder:(_)=>PickMap(initial:point)));if(result!=null)setState(()=>point=result);},icon:const Icon(Icons.map_outlined),label:const Text('Pick exact location on map')),
 if(point!=null)Text('Pin: ${point!.latitude.toStringAsFixed(5)}, ${point!.longitude.toStringAsFixed(5)}'),
 SwitchListTile(value:available,onChanged:(v)=>setState(()=>available=v),title:const Text('Available for booking')),
 CheckboxListTile(value:safety,onChanged:(v)=>setState(()=>safety=v??false),title:const Text('I am authorized to share this charger and confirm its safe installation.'),controlAffinity:ListTileControlAffinity.leading),
 const SizedBox(height:10),FilledButton.icon(onPressed:busy?null:publish,icon:const Icon(Icons.public),label:Padding(padding:const EdgeInsets.all(14),child:Text(busy?'Publishing…':'Go live on the map'))),
 ])));
}
class PickMap extends StatefulWidget{const PickMap({super.key,this.initial});final LatLng? initial;@override State<PickMap> createState()=>_PickMapState();}
class _PickMapState extends State<PickMap>{
  late LatLng point;
  int mapVersion = 0;
  @override void initState(){super.initState();point=widget.initial??const LatLng(9.9312,76.2673);}
  Future<void> useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Enable location services.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is needed.');
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() { point = LatLng(position.latitude, position.longitude); mapVersion++; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pick charger location'), actions: [
      TextButton(onPressed: () => Navigator.pop(context, point), child: const Text('Confirm')),
    ]),
    body: LeafletMapView(
      key: ValueKey(mapVersion),
      initial: point,
      pickMode: true,
      onPointSelected: (value) => setState(() => point = value),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: useCurrentLocation,
      icon: const Icon(Icons.my_location),
      label: const Text('Use current location'),
    ),
  );
}
