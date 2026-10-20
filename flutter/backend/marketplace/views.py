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
from rest_framework.exceptions import ValidationError, PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import Charger, Booking, Review, AppNotification
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
    """Persist an in-app notification; no push-notification provider is configured."""
    return AppNotification.objects.create(
        user=user, title=title, body=body, kind=kind, booking=booking
    )

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
        # Lock the charger row so simultaneous host actions cannot accept overlapping sessions.
        Charger.objects.select_for_update().get(pk=booking.charger_id)
        if accept and Booking.objects.filter(charger_id=booking.charger_id,status="accepted").exclude(pk=booking.pk).exists():
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
        if actual<Decimal("0.01") or actual>Decimal("1000"): raise ValidationError({"actual_kwh":"Energy must be at least 0.01 and no more than 1000 kWh."})
        actual=actual.quantize(Decimal("0.01"),rounding=ROUND_HALF_UP)
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

class BookingMarkPaidView(APIView):
    """Host confirms receipt of offline/manual payment for a completed session."""
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, pk):
        try:
            booking = Booking.objects.select_for_update().select_related(
                "charger", "driver"
            ).get(pk=pk)
        except Booking.DoesNotExist:
            return Response({"detail": "Booking not found."}, status=404)

        if booking.charger.host_id != request.user.id:
            raise PermissionDenied("Only the charger host can confirm payment.")
        if booking.status != "completed" or booking.total_amount is None:
            raise ValidationError("Only a completed charging session can be marked as paid.")
        if booking.payment_status == "paid":
            raise ValidationError("This booking is already marked as paid.")

        booking.payment_status = "paid"
        booking.save(update_fields=["payment_status"])
        notify_user(
            booking.driver,
            "Payment marked as received",
            f"The host confirmed receipt of ₹{booking.total_amount} for {booking.charger.title}.",
            "payment_received",
            booking,
        )
        return Response(BookingSerializer(booking, context={"request": request}).data)


class NotificationListView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    def get(self,request):
        items=AppNotification.objects.filter(user=request.user).select_related("booking")[:100]
        return Response([{"id":n.id,"title":n.title,"body":n.body,"kind":n.kind,"booking_id":n.booking_id,"is_read":n.is_read,"created_at":n.created_at.isoformat()} for n in items])

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
