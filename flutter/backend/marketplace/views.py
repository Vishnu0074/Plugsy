import base64
import hashlib
import hmac
import json
import math
import os
import urllib.error
import urllib.request
from decimal import Decimal, ROUND_HALF_UP

from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.exceptions import ValidationError, PermissionDenied, APIException
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import Charger, Booking, Review, Payment, DeviceToken, AppNotification
from .serializers import RegisterSerializer, ChargerSerializer, BookingSerializer, ReviewSerializer

User = get_user_model()

def token_payload(user):
    refresh = RefreshToken.for_user(user)
    return {"refresh":str(refresh),"access":str(refresh.access_token),"user":{"id":user.id,"username":user.username,"email":user.email,"wants_to_host":user.wants_to_host}}

class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]
    def post(self,request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(token_payload(user),status=status.HTTP_201_CREATED)

class LoginView(APIView):
    permission_classes = [permissions.AllowAny]
    def post(self,request):
        identity = str(request.data.get("username","")).strip()
        password = request.data.get("password","")
        user = User.objects.filter(email__iexact=identity).first() if "@" in identity else User.objects.filter(username__iexact=identity).first()
        if not user or not user.check_password(password) or not user.is_active:
            return Response({"detail":"Invalid username/email or password."},status=status.HTTP_400_BAD_REQUEST)
        return Response(token_payload(user))

def notify_user(user, title, body, kind, booking=None):
    """Persist every event; send an FCM push too when Firebase credentials are configured."""
    notice = AppNotification.objects.create(user=user,title=title,body=body,kind=kind,booking=booking)
    tokens = list(DeviceToken.objects.filter(user=user).values_list("token",flat=True))
    service_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    if tokens and service_json:
        try:
            import firebase_admin
            from firebase_admin import credentials, messaging
            if not firebase_admin._apps:
                credentials_obj = credentials.Certificate(json.loads(service_json))
                firebase_admin.initialize_app(credentials_obj)
            for token in tokens:
                try:
                    messaging.send(messaging.Message(
                        notification=messaging.Notification(title=title,body=body),
                        data={"kind":kind,"booking_id":str(booking.id if booking else "")},
                        token=token,
                    ))
                except Exception:
                    # Invalid tokens are cleaned up rather than breaking the booking operation.
                    DeviceToken.objects.filter(token=token).delete()
        except Exception:
            # In-app notifications remain available if Firebase is not configured.
            pass
    return notice

def haversine_km(lat1,lon1,lat2,lon2):
    r=6371.0
    p1,p2=math.radians(lat1),math.radians(lat2)
    dp,dl=math.radians(lat2-lat1),math.radians(lon2-lon1)
    a=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*r*math.asin(min(1,math.sqrt(a)))

class ChargerListCreateView(generics.ListCreateAPIView):
    serializer_class = ChargerSerializer
    def get_permissions(self):
        return [permissions.IsAuthenticated()] if self.request.method=="POST" else [permissions.AllowAny()]
    def get_queryset(self):
        qs=Charger.objects.filter(is_published=True,is_available=True).select_related("host").prefetch_related("reviews")
        lat,lng=self.request.query_params.get("lat"),self.request.query_params.get("lng")
        self.distances={}
        if lat is not None and lng is not None:
            try:
                lat,lng=float(lat),float(lng)
                if not (-90<=lat<=90 and -180<=lng<=180): raise ValueError()
            except ValueError: raise ValidationError("lat/lng must be valid coordinates.")
            items=list(qs)
            for c in items: self.distances[c.id]=round(haversine_km(lat,lng,float(c.latitude),float(c.longitude)),2)
            items.sort(key=lambda c:self.distances[c.id])
            return items
        return qs
    def get_serializer_context(self):
        ctx=super().get_serializer_context()
        ctx["distances"]=getattr(self,"distances",{})
        return ctx
    def perform_create(self,serializer):
        if not self.request.user.wants_to_host: raise PermissionDenied("Enable charger hosting on your account before listing a charger.")
        if self.request.data.get("is_published") and not self.request.data.get("safety_confirmed"):
            raise ValidationError({"safety_confirmed":"Safety confirmation is required before publishing."})
        serializer.save(host=self.request.user)

class BookingListCreateView(generics.ListCreateAPIView):
    serializer_class=BookingSerializer
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self):
        from django.db.models import Q
        return Booking.objects.filter(Q(driver=self.request.user)|Q(charger__host=self.request.user)).select_related("charger","driver")
    @transaction.atomic
    def perform_create(self,serializer):
        try: charger=Charger.objects.select_for_update().get(pk=self.request.data.get("charger"),is_published=True,is_available=True)
        except (Charger.DoesNotExist,ValueError,TypeError): raise ValidationError({"charger":"This charger is not available."})
        if charger.host_id==self.request.user.id: raise ValidationError("You cannot book your own charger.")
        if Booking.objects.filter(charger=charger,driver=self.request.user,status__in=["pending","accepted"]).exists():
            raise ValidationError("You already have an active request for this charger.")
        booking=serializer.save(charger=charger,driver=self.request.user)
        notify_user(charger.host,"New Plugsy charging request",f"@{self.request.user.username} requested {booking.estimated_kwh} kWh at {charger.title}.","booking_request",booking)

class BookingRespondView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    @transaction.atomic
    def post(self,request,pk):
        try: booking=Booking.objects.select_for_update().select_related("charger","driver").get(pk=pk)
        except Booking.DoesNotExist: return Response({"detail":"Booking not found."},status=404)
        if booking.charger.host_id!=request.user.id: raise PermissionDenied("Only the charger host can respond.")
        if booking.status!="pending": raise ValidationError("This booking has already been answered.")
        accept=request.data.get("accept")
        if not isinstance(accept,bool): raise ValidationError({"accept":"Must be true or false."})
        if accept and Booking.objects.filter(charger=booking.charger,status="accepted").exclude(pk=booking.pk).exists():
            raise ValidationError("This charger already has an accepted booking. Complete that session before accepting another.")
        booking.status="accepted" if accept else "declined"
        booking.responded_at=timezone.now()
        booking.save(update_fields=["status","responded_at"])
        notify_user(booking.driver,"Charger request accepted" if accept else "Charger request declined",
                    f"@{request.user.username} {'accepted' if accept else 'declined'} your request for {booking.charger.title}.",
                    "booking_accepted" if accept else "booking_declined",booking)
        return Response(BookingSerializer(booking,context={"request":request}).data)

class BookingStartView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    @transaction.atomic
    def post(self,request,pk):
        try: booking=Booking.objects.select_for_update().select_related("charger","driver").get(pk=pk)
        except Booking.DoesNotExist: return Response({"detail":"Booking not found."},status=404)
        if booking.charger.host_id!=request.user.id: raise PermissionDenied("Only the host can start the session.")
        if booking.status!="accepted": raise ValidationError("Only an accepted booking can be started.")
        if booking.session_started_at: raise ValidationError("This session has already started.")
        booking.session_started_at=timezone.now()
        booking.save(update_fields=["session_started_at"])
        notify_user(booking.driver,"Charging session started",f"Your session at {booking.charger.title} has started.","session_started",booking)
        return Response(BookingSerializer(booking,context={"request":request}).data)

class BookingCompleteView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    @transaction.atomic
    def post(self,request,pk):
        try: booking=Booking.objects.select_for_update().select_related("charger","driver").get(pk=pk)
        except Booking.DoesNotExist: return Response({"detail":"Booking not found."},status=404)
        if booking.charger.host_id!=request.user.id: raise PermissionDenied("Only the host can complete this session.")
        if booking.status!="accepted" or not booking.session_started_at:
            raise ValidationError("Start an accepted session before completing it.")
        if booking.actual_kwh is not None: raise ValidationError("This session has already been completed.")
        try: actual=Decimal(str(request.data.get("actual_kwh")))
        except Exception: raise ValidationError({"actual_kwh":"Enter the measured energy in kWh."})
        if actual<=0 or actual>Decimal("1000"): raise ValidationError({"actual_kwh":"Energy must be greater than 0 and no more than 1000 kWh."})
        total=(actual*booking.charger.price_per_kwh).quantize(Decimal("0.01"),rounding=ROUND_HALF_UP)
        # Platform fee remains zero until a disclosed fee policy is configured.
        booking.actual_kwh=actual
        booking.total_amount=total
        booking.platform_fee=Decimal("0.00")
        booking.status="completed"
        booking.completed_at=timezone.now()
        booking.save(update_fields=["actual_kwh","total_amount","platform_fee","status","completed_at"])
        notify_user(booking.driver,"Charging session complete",f"{actual} kWh recorded. Final amount: ₹{total}. Complete payment to leave a review.","session_completed",booking)
        return Response(BookingSerializer(booking,context={"request":request}).data)

class CreatePaymentOrderView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    def post(self,request,pk):
        try: booking=Booking.objects.select_related("charger","driver").get(pk=pk,driver=request.user)
        except Booking.DoesNotExist: return Response({"detail":"Booking not found."},status=404)
        if booking.status!="completed" or booking.total_amount is None:
            raise ValidationError("Payment becomes available after the host records the completed charging session.")
        if booking.payment_status=="paid":
            raise ValidationError("This booking has already been paid.")
        key_id=os.getenv("RAZORPAY_KEY_ID","")
        key_secret=os.getenv("RAZORPAY_KEY_SECRET","")
        if not key_id or not key_secret:
            raise APIException("Online payments are not configured. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET.")
        amount_paise=int((booking.total_amount*100).quantize(Decimal("1"),rounding=ROUND_HALF_UP))
        payload=json.dumps({"amount":amount_paise,"currency":"INR","receipt":f"plugsy_booking_{booking.id}","notes":{"booking_id":str(booking.id)}}).encode()
        auth=base64.b64encode(f"{key_id}:{key_secret}".encode()).decode()
        req=urllib.request.Request("https://api.razorpay.com/v1/orders",data=payload,headers={"Authorization":f"Basic {auth}","Content-Type":"application/json"},method="POST")
        try:
            with urllib.request.urlopen(req,timeout=15) as resp: data=json.loads(resp.read().decode())
        except (urllib.error.URLError,urllib.error.HTTPError,TimeoutError) as exc:
            raise APIException(f"Payment provider order creation failed: {exc}")
        payment,created=Payment.objects.get_or_create(booking=booking,defaults={"order_id":data["id"],"amount_paise":amount_paise})
        if not created:
            if payment.status=="paid": raise ValidationError("This booking has already been paid.")
            payment.order_id=data["id"]; payment.amount_paise=amount_paise; payment.status="created"; payment.save(update_fields=["order_id","amount_paise","status"])
        return Response({"key_id":key_id,"order_id":data["id"],"amount":amount_paise,"currency":"INR","booking_id":booking.id,"description":booking.charger.title})

class VerifyPaymentView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    @transaction.atomic
    def post(self,request,pk):
        try: booking=Booking.objects.select_for_update().select_related("charger").get(pk=pk,driver=request.user)
        except Booking.DoesNotExist: return Response({"detail":"Booking not found."},status=404)
        try: payment=Payment.objects.select_for_update().get(booking=booking)
        except Payment.DoesNotExist: raise ValidationError("Create a payment order first.")
        payment_id=str(request.data.get("razorpay_payment_id",""))
        order_id=str(request.data.get("razorpay_order_id",""))
        signature=str(request.data.get("razorpay_signature",""))
        if order_id!=payment.order_id: raise ValidationError("Payment order does not match this booking.")
        secret=os.getenv("RAZORPAY_KEY_SECRET","")
        if not secret: raise APIException("Payment verification is not configured.")
        expected=hmac.new(secret.encode(),f"{order_id}|{payment_id}".encode(),hashlib.sha256).hexdigest()
        if not payment_id or not hmac.compare_digest(expected,signature): raise ValidationError("Payment signature verification failed.")
        # Verify provider-side status and order association as well as the checkout signature.
        auth=base64.b64encode(f"{os.getenv('RAZORPAY_KEY_ID','')}:{secret}".encode()).decode()
        payment_req=urllib.request.Request(
            f"https://api.razorpay.com/v1/payments/{payment_id}",
            headers={"Authorization":f"Basic {auth}"},
            method="GET",
        )
        try:
            with urllib.request.urlopen(payment_req,timeout=15) as resp:
                provider_payment=json.loads(resp.read().decode())
        except (urllib.error.URLError,urllib.error.HTTPError,TimeoutError) as exc:
            raise APIException(f"Could not verify payment with Razorpay: {exc}")
        if provider_payment.get("order_id") != payment.order_id:
            raise ValidationError("Payment does not belong to this order.")
        if provider_payment.get("status") != "captured":
            raise ValidationError("Payment is not captured yet. Check again after capture.")
        if int(provider_payment.get("amount",0)) != payment.amount_paise:
            raise ValidationError("The captured amount does not match the booking total.")
        if payment.status!="paid":
            payment.payment_id=payment_id; payment.signature=signature; payment.status="paid"; payment.paid_at=timezone.now()
            payment.save(update_fields=["payment_id","signature","status","paid_at"])
            booking.payment_status="paid"; booking.save(update_fields=["payment_status"])
            notify_user(booking.charger.host,"Plugsy payment received",f"Payment of ₹{booking.total_amount} for {booking.charger.title} was verified.","payment_received",booking)
        return Response({"status":"paid","booking_id":booking.id,"amount":str(booking.total_amount)})

class DeviceTokenView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    def post(self,request):
        token=str(request.data.get("token","")).strip()
        platform=str(request.data.get("platform","unknown"))[:20]
        if len(token)<20: raise ValidationError({"token":"A valid FCM device token is required."})
        DeviceToken.objects.update_or_create(token=token,defaults={"user":request.user,"platform":platform})
        return Response({"registered":True},status=status.HTTP_200_OK)

class NotificationListView(generics.ListAPIView):
    permission_classes=[permissions.IsAuthenticated]
    def get_queryset(self): return AppNotification.objects.filter(user=self.request.user)[:100]

class NotificationReadView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    def post(self,request,pk):
        updated=AppNotification.objects.filter(pk=pk,user=request.user).update(is_read=True)
        if not updated: return Response({"detail":"Notification not found."},status=404)
        return Response({"read":True})

class ReviewListCreateView(generics.ListCreateAPIView):
    serializer_class=ReviewSerializer
    def get_permissions(self):
        return [permissions.IsAuthenticated()] if self.request.method=="POST" else [permissions.AllowAny()]
    def get_queryset(self):
        qs=Review.objects.select_related("author","charger")
        charger_id=self.request.query_params.get("charger")
        return qs.filter(charger_id=charger_id) if charger_id else qs
    def perform_create(self,serializer): serializer.save(author=self.request.user)
