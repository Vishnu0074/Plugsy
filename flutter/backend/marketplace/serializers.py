from django.contrib.auth import get_user_model
from rest_framework import serializers
from .models import Charger, Booking, Review
User = get_user_model()

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    class Meta:
        model = User
        fields = ["id", "email", "username", "password", "wants_to_host"]
    def create(self, validated_data):
        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user

class ChargerSerializer(serializers.ModelSerializer):
    latitude = serializers.SerializerMethodField()
    longitude = serializers.SerializerMethodField()
    host_username = serializers.CharField(source="host.username", read_only=True)
    average_rating = serializers.SerializerMethodField()
    review_count = serializers.SerializerMethodField()
    distance_km = serializers.SerializerMethodField()
    class Meta:
        model = Charger
        fields = ["id","title","latitude","longitude","price_per_kwh","power_kw","connector_type","approximate_address","is_available","is_published","host_username","average_rating","review_count","distance_km","created_at"]
        read_only_fields = ["id","host_username","average_rating","review_count","distance_km","created_at"]
    def _may_see_exact_location(self, obj):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False
        if obj.host_id == request.user.id:
            return True
        return Booking.objects.filter(charger=obj, driver=request.user, status__in=["accepted","completed"]).exists()
    def get_latitude(self, obj):
        value = float(obj.latitude)
        return value if self._may_see_exact_location(obj) else round(value, 3)
    def get_longitude(self, obj):
        value = float(obj.longitude)
        return value if self._may_see_exact_location(obj) else round(value, 3)
    def get_average_rating(self,obj):
        from django.db.models import Avg
        return round(obj.reviews.aggregate(v=Avg("rating"))["v"] or 0,1)
    def get_review_count(self,obj): return obj.reviews.count()
    def get_distance_km(self,obj): return self.context.get("distances",{}).get(obj.id)

class BookingSerializer(serializers.ModelSerializer):
    charger_title = serializers.CharField(source="charger.title",read_only=True)
    charger_host = serializers.CharField(source="charger.host.username",read_only=True)
    driver_username = serializers.CharField(source="driver.username",read_only=True)
    class Meta:
        model = Booking
        fields = ["id","charger","charger_title","charger_host","driver","driver_username","status","requested_at","responded_at","estimated_kwh","total_amount","platform_fee","payment_status"]
        read_only_fields = ["id","driver","status","requested_at","responded_at","total_amount","platform_fee","payment_status","charger_title","charger_host","driver_username"]

class ReviewSerializer(serializers.ModelSerializer):
    author_username = serializers.CharField(source="author.username",read_only=True)
    class Meta:
        model = Review
        fields = ["id","charger","booking","rating","comment","author_username","created_at"]
        read_only_fields = ["id","booking","author_username","created_at"]
    def validate(self,attrs):
        booking = attrs.get("booking")
        if booking.driver_id != self.context["request"].user.id or booking.status != "completed":
            raise serializers.ValidationError("Only a driver with a completed booking can review this charger.")
        if booking.charger_id != attrs["charger"].id:
            raise serializers.ValidationError("Review charger must match the completed booking.")
        return attrs
