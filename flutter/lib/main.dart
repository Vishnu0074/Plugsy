import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const apiBase = String.fromEnvironment('PLUGSY_API_BASE_URL', defaultValue: 'http://10.0.2.2:8000/api');

final localNotifications = FlutterLocalNotificationsPlugin();
const bookingChannel = AndroidNotificationChannel('plugsy_booking_alerts','Plugsy booking alerts',description:'Booking, charging-session, and payment updates',importance:Importance.max,playSound:true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const initSettings=InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher'),iOS:DarwinInitializationSettings());
  await localNotifications.initialize(initSettings);
  await localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(bookingChannel);
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onMessage.listen((message) async {
      final title=message.notification?.title ?? 'Plugsy update';
      final body=message.notification?.body ?? 'You have a new booking update.';
      await localNotifications.show(DateTime.now().millisecondsSinceEpoch.remainder(100000),title,body,NotificationDetails(
        android:AndroidNotificationDetails(bookingChannel.id,bookingChannel.name,channelDescription:bookingChannel.description,importance:Importance.max,priority:Priority.high,playSound:true),
        iOS:const DarwinNotificationDetails(presentAlert:true,presentBadge:true,presentSound:true),
      ));
    });
  } catch (_) { /* Configure Firebase to enable remote and local booking alerts. */ }
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
    if (access != null) { await _registerPushToken(); await loadChargers(); }
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
    await _registerPushToken();
    await loadChargers();
  }
  Future<void> _registerPushToken() async {
    try {
      if (Firebase.apps.isEmpty || access == null) return;
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        request('/devices/register/', method: 'POST', body: {'token': token, 'platform': 'mobile'}).catchError((_) => <String,dynamic>{});
      });
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await request('/devices/register/', method: 'POST', body: {'token': token, 'platform': 'mobile'});
    } catch (_) { /* The app remains usable without Firebase configuration. */ }
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
  int tab=0; List<dynamic> bookings=[]; List<dynamic> payouts=[]; bool busy=false; LatLng? userPoint; late Razorpay _razorpay; int? _paymentBookingId;
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
      try { final p=await context.read<PlugsyState>().request('/payouts/'); payouts=p is List?p:(p['results'] as List? ?? []); } catch (_) { payouts=[]; }
    } catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void initState(){super.initState();_razorpay=Razorpay();_razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,_paymentSuccess);_razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,_paymentError);_razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET,_externalWallet);WidgetsBinding.instance.addPostFrameCallback((_)=>nearby());}
  @override void dispose(){_razorpay.clear();super.dispose();}
  void _paymentSuccess(PaymentSuccessResponse response) async {
    final id=_paymentBookingId;
    if(id==null)return;
    try {
      await context.read<PlugsyState>().request('/bookings/$id/verify-payment/',method:'POST',body:{'razorpay_payment_id':response.paymentId,'razorpay_order_id':response.orderId,'razorpay_signature':response.signature});
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Payment verified successfully.')));await loadBookings();}
    } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Payment verification failed: $e'))); }
    finally {_paymentBookingId=null;}
  }
  void _paymentError(PaymentFailureResponse response){_paymentBookingId=null;if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Payment was not completed: ${response.message??response.code}')));}
  void _externalWallet(ExternalWalletResponse response){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('External wallet selected: ${response.walletName??'wallet'}')));}
  Future<void> payForBooking(dynamic booking) async {
    try {
      final id=booking['id'] as int;
      final order=await context.read<PlugsyState>().request('/bookings/$id/payment-order/',method:'POST');
      _paymentBookingId=id;
      _razorpay.open({'key':order['key_id'],'amount':order['amount'],'currency':order['currency'],'name':'Plugsy','order_id':order['order_id'],'description':'EV charging session','prefill':{'email':''},'theme':{'color':'#B7F36B'}});
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
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
      const SizedBox(height:12),const Text('Choose an estimated energy amount. The host must accept the request. You will pay the final amount after the host records the completed session.'),
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
    if(payouts.isNotEmpty) ...[
      const SizedBox(height:16),const Text('Host payouts',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      ...payouts.map((p)=>Card(child:ListTile(leading:const Icon(Icons.account_balance_wallet_outlined),title:Text('Booking #${p['booking_id']} · ₹${p['amount_rupees']}'),subtitle:Text('${p['status']} · ${p['error_message']??''}'),trailing:p['status']=='transferred'?const Icon(Icons.check_circle,color:Colors.green):const Icon(Icons.schedule)))),
    ],
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
      } else if(!isHost&&state=='completed'&&!paid){
        action=FilledButton(onPressed:()=>payForBooking(b),child:const Text('Pay'));
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
        if(state=='completed'&&!paid)const Text('Session is complete. Driver payment is due before a review.',style:TextStyle(color:Colors.black54)),
        if(action!=null)Align(alignment:Alignment.centerRight,child:action),
      ])));
    }),
  ]));
  Future<void> respond(dynamic id,bool accept)async{try{await context.read<PlugsyState>().request('/bookings/$id/respond/',method:'POST',body:{'accept':accept});await loadBookings();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
}

class ChargerMap extends StatelessWidget {
  const ChargerMap({super.key,required this.chargers,this.initial}); final List<dynamic> chargers; final LatLng? initial;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Chargers nearby')),body:FlutterMap(options:MapOptions(initialCenter:initial ?? (chargers.isNotEmpty ? LatLng(double.parse(chargers.first['latitude'].toString()),double.parse(chargers.first['longitude'].toString())) : const LatLng(9.9312,76.2673)),initialZoom:11),children:[
    TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.plugsy.app'),
    MarkerLayer(markers:chargers.map((c)=>Marker(point:LatLng(double.parse(c['latitude'].toString()),double.parse(c['longitude'].toString())),width:48,height:48,child:GestureDetector(onTap:()=>showModalBottomSheet(context:context,builder:(_)=>Padding(padding:const EdgeInsets.all(20),child:Text('${c['title']} · ₹${c['price_per_kwh']}/kWh · ★ ${c['average_rating']??0}'))),child:const Icon(Icons.location_pin,color:Colors.green,size:40)))).toList()),
    const RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')]),
  ]));
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
class _PickMapState extends State<PickMap>{late LatLng point;@override void initState(){super.initState();point=widget.initial??const LatLng(9.9312,76.2673);}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Pick charger location'),actions:[TextButton(onPressed:()=>Navigator.pop(context,point),child:const Text('Confirm'))]),body:FlutterMap(options:MapOptions(initialCenter:point,initialZoom:14,onTap:(_,p)=>setState(()=>point=p)),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.plugsy.app'),MarkerLayer(markers:[Marker(point:point,width:48,height:48,child:const Icon(Icons.location_pin,color:Colors.red,size:42))]),const RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')])]),floatingActionButton:FloatingActionButton.extended(onPressed:()=>Navigator.pop(context,point),icon:const Icon(Icons.check),label:const Text('Use this location')));}
