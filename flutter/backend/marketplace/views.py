import math
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.exceptions import ValidationError, PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from .models import Charger, Booking, Review
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
    def perform_create(self,serializer):
        try: charger=Charger.objects.get(pk=self.request.data.get("charger"),is_published=True,is_available=True)
        except (Charger.DoesNotExist,ValueError,TypeError): raise ValidationError({"charger":"This charger is not available."})
        if charger.host_id==self.request.user.id: raise ValidationError("You cannot book your own charger.")
        if Booking.objects.filter(charger=charger,driver=self.request.user,status__in=["pending","accepted"]).exists():
            raise ValidationError("You already have an active request for this charger.")
        serializer.save(charger=charger,driver=self.request.user)

class BookingRespondView(APIView):
    permission_classes=[permissions.IsAuthenticated]
    @transaction.atomic
    def post(self,request,pk):
        try: booking=Booking.objects.select_for_update().select_related("charger").get(pk=pk)
        except Booking.DoesNotExist: return Response({"detail":"Booking not found."},status=404)
        if booking.charger.host_id!=request.user.id: raise PermissionDenied("Only the charger host can respond.")
        if booking.status!="pending": raise ValidationError("This booking has already been answered.")
        accept=request.data.get("accept")
        if not isinstance(accept,bool): raise ValidationError({"accept":"Must be true or false."})
        booking.status="accepted" if accept else "declined"
        booking.responded_at=timezone.now()
        booking.save(update_fields=["status","responded_at"])
        return Response(BookingSerializer(booking).data)

class ReviewListCreateView(generics.ListCreateAPIView):
    serializer_class=ReviewSerializer
    def get_permissions(self):
        return [permissions.IsAuthenticated()] if self.request.method=="POST" else [permissions.AllowAny()]
    def get_queryset(self):
        qs=Review.objects.select_related("author","charger")
        charger_id=self.request.query_params.get("charger")
        return qs.filter(charger_id=charger_id) if charger_id else qs
    def perform_create(self,serializer): serializer.save(author=self.request.user)
